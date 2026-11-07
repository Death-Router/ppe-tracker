import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.db import commit_or_400
from app.db.session import get_db
from app.models.ppe_size import PpeSize
from app.models.ppe_size_group import PpeSizeGroup
from app.schemas.ppe_size import PpeSizeCreate, PpeSizeRead
from app.utils.broadcast import broadcast

router = APIRouter(prefix="/ppe_sizes", tags=["Справочник: Размеры СИЗ"])

@router.post("/", response_model=PpeSizeRead, status_code=status.HTTP_201_CREATED)
async def create_size(size_in: PpeSizeCreate, db: AsyncSession = Depends(get_db)):
    group_res = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == size_in.size_group_id))
    if not group_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Размерная группа не найдена")

    db_size = PpeSize(**size_in.model_dump())
    db.add(db_size)
    await commit_or_400(db, "Такой размер уже существует для этой группы")
    
    await db.refresh(db_size)
    await broadcast(
        0,
        {
            "event": "size_updated",
            "id": db_size.id,
            "size_group_id": db_size.size_group_id,
        },
    )
    return db_size

@router.get("/", response_model=list[PpeSizeRead])
async def get_sizes(size_group_id: int | None = None, gender: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(PpeSize)
    if size_group_id is not None:
        query = query.where(PpeSize.size_group_id == size_group_id)
    if gender:
        query = query.where(PpeSize.gender == gender)

    # Порядок: сначала пол (М, Ж, затем унисекс), внутри — по числу.
    # Обычная сортировка строк ставила «44» перед «34» и «300» перед «40»:
    # размеры — это числа, а не текст. Диапазоны вроде «40-42» приводим к
    # первому числу, чтобы они вставали на своё место.
    numeric = sa.cast(
        sa.func.nullif(sa.func.regexp_replace(PpeSize.size_value, r"[^0-9].*$", "", "g"), ""),
        sa.Integer,
    )
    query = query.order_by(
        sa.case((PpeSize.gender == "М", 0), (PpeSize.gender == "Ж", 1), else_=2),
        numeric.nulls_last(),
        PpeSize.size_value,
    )

    result = await db.execute(query)
    return result.scalars().all()

@router.delete("/{size_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_size(size_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSize).where(PpeSize.id == size_id))
    db_size = result.scalar_one_or_none()
    if not db_size:
        raise HTTPException(status_code=404, detail="Размер не найден")
    # Группа нужна после удаления: по ней страница решает, перерисовывать ли
    # открытый список размеров
    size_group_id = db_size.size_group_id
    await db.delete(db_size)
    await db.commit()

    await broadcast(
        0, {"event": "size_updated", "id": size_id, "size_group_id": size_group_id}
    )

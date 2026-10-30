from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.ppe_size import PpeSize
from app.models.ppe_size_group import PpeSizeGroup
from app.schemas.ppe_size import PpeSizeCreate, PpeSizeRead

router = APIRouter(prefix="/ppe_sizes", tags=["Справочник: Размеры СИЗ"])

@router.post("/", response_model=PpeSizeRead, status_code=status.HTTP_201_CREATED)
async def create_size(size_in: PpeSizeCreate, db: AsyncSession = Depends(get_db)):
    group_res = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == size_in.size_group_id))
    if not group_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Размерная группа не найдена")

    db_size = PpeSize(**size_in.model_dump())
    db.add(db_size)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такой размер уже существует для этой группы")
    
    await db.refresh(db_size)
    return db_size

@router.get("/", response_model=list[PpeSizeRead])
async def get_sizes(size_group_id: int | None = None, gender: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(PpeSize)
    if size_group_id is not None:
        query = query.where(PpeSize.size_group_id == size_group_id)
    if gender:
        query = query.where(PpeSize.gender == gender)
    result = await db.execute(query)
    return result.scalars().all()

@router.delete("/{size_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_size(size_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSize).where(PpeSize.id == size_id))
    db_size = result.scalar_one_or_none()
    if not db_size:
        raise HTTPException(status_code=404, detail="Размер не найден")
    await db.delete(db_size)
    await db.commit()

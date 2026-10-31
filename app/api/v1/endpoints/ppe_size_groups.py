from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models.ppe_size_group import PpeSizeGroup
from app.schemas.ppe_size_group import PpeSizeGroupCreate, PpeSizeGroupRead, PpeSizeGroupUpdate

router = APIRouter(prefix="/ppe_size_groups", tags=["Справочник: Размерные группы"])

@router.post("/", response_model=PpeSizeGroupRead, status_code=status.HTTP_201_CREATED)
async def create_group(group_in: PpeSizeGroupCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.name == group_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая группа уже существует")
    db_group = PpeSizeGroup(**group_in.model_dump())
    db.add(db_group)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такая группа уже существует") from exc
    await db.refresh(db_group)
    return db_group

@router.get("/", response_model=list[PpeSizeGroupRead])
async def get_groups(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).order_by(PpeSizeGroup.name))
    return result.scalars().all()

@router.put("/{group_id}", response_model=PpeSizeGroupRead)
async def update_group(group_id: int, group_in: PpeSizeGroupUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == group_id))
    db_group = result.scalar_one_or_none()
    if not db_group:
        raise HTTPException(status_code=404, detail="Группа не найдена")
    if db_group.version != group_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = group_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_group, field, value)
    db_group.version += 1
    await db.commit()
    await db.refresh(db_group)
    return db_group

@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_group(group_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == group_id))
    db_group = result.scalar_one_or_none()
    if not db_group:
        raise HTTPException(status_code=404, detail="Группа не найдена")
    try:
        await db.delete(db_group)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить группу, есть привязанные СИЗ или размеры") from exc

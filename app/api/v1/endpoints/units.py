from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.unit import Unit
from app.schemas.unit import UnitCreate, UnitRead

router = APIRouter(prefix="/units", tags=["Справочник: Единицы измерения"])

@router.post("/", response_model=UnitRead, status_code=status.HTTP_201_CREATED)
async def create_unit(unit_in: UnitCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).where(Unit.name == unit_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая единица измерения уже существует")
    
    db_unit = Unit(**unit_in.model_dump())
    db.add(db_unit)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка при создании единицы")
    
    await db.refresh(db_unit)
    return db_unit

@router.get("/", response_model=list[UnitRead])
async def get_units(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).order_by(Unit.name))
    return result.scalars().all()

@router.delete("/{unit_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_unit(unit_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).where(Unit.id == unit_id))
    db_unit = result.scalar_one_or_none()
    if not db_unit:
        raise HTTPException(status_code=404, detail="Единица не найдена")
    try:
        await db.delete(db_unit)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить единицу, есть привязанные СИЗ")

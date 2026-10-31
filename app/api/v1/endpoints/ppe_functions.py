from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.ppe_function import PpeFunction
from app.schemas.ppe_function import PpeFunctionCreate, PpeFunctionRead, PpeFunctionUpdate

router = APIRouter(prefix="/ppe_functions", tags=["Справочник: Функции СИЗ"])

@router.post("/", response_model=PpeFunctionRead, status_code=status.HTTP_201_CREATED)
async def create_function(func_in: PpeFunctionCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.name == func_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая функция уже существует")
    db_func = PpeFunction(**func_in.model_dump())
    db.add(db_func)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такая функция уже существует")
    await db.refresh(db_func)
    return db_func

@router.get("/", response_model=list[PpeFunctionRead])
async def get_functions(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).order_by(PpeFunction.name))
    return result.scalars().all()

@router.put("/{func_id}", response_model=PpeFunctionRead)
async def update_function(func_id: int, func_in: PpeFunctionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.id == func_id))
    db_func = result.scalar_one_or_none()
    if not db_func:
        raise HTTPException(status_code=404, detail="Функция не найдена")
    if db_func.version != func_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = func_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_func, field, value)
    db_func.version += 1
    await db.commit()
    await db.refresh(db_func)
    return db_func

@router.delete("/{func_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_function(func_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.id == func_id))
    db_func = result.scalar_one_or_none()
    if not db_func:
        raise HTTPException(status_code=404, detail="Функция не найдена")
    try:
        await db.delete(db_func)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить функцию, есть привязанные СИЗ")

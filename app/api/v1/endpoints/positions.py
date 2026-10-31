from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.position import Position
from app.models.department import Department
from app.schemas.position import PositionCreate, PositionRead, PositionUpdate

router = APIRouter(prefix="/positions", tags=["Справочник: Должности"])

@router.post("/", response_model=PositionRead, status_code=status.HTTP_201_CREATED)
async def create_position(pos_in: PositionCreate, db: AsyncSession = Depends(get_db)):
    cat_result = await db.execute(select(Department).where(Department.id == pos_in.department_id))
    if not cat_result.scalar_one_or_none(): raise HTTPException(status_code=404, detail="Подразделение не найдено")
    db_pos = Position(**pos_in.model_dump())
    db.add(db_pos)
    await db.commit()
    await db.refresh(db_pos)
    result = await db.execute(select(Position).where(Position.id == db_pos.id).options(selectinload(Position.department)))
    return result.scalar_one()

@router.get("/", response_model=list[PositionRead])
async def get_positions(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).options(selectinload(Position.department)))
    return result.scalars().all()

@router.get("/{pos_id}", response_model=PositionRead)
async def get_position(pos_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id).options(selectinload(Position.department)))
    pos = result.scalar_one_or_none()
    if not pos: raise HTTPException(status_code=404, detail="Не найдено")
    return pos

@router.put("/{pos_id}", response_model=PositionRead)
async def update_position(pos_id: int, pos_in: PositionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id))
    db_pos = result.scalar_one_or_none()
    if not db_pos: raise HTTPException(status_code=404, detail="Не найдено")
    if db_pos.version != pos_in.version: raise HTTPException(status_code=409, detail="Данные устарели")
    # Без проверки несуществующий department_id ронял бы commit в 500 (FK)
    if pos_in.department_id is not None:
        dept_res = await db.execute(select(Department).where(Department.id == pos_in.department_id))
        if not dept_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Подразделение не найдено")
    for field, value in pos_in.model_dump(exclude_unset=True, exclude={"version"}).items():
        setattr(db_pos, field, value)
    db_pos.version += 1
    await db.commit()
    try: await manager.broadcast_to_employee(0, {"event": "position_updated", "id": pos_id})
    except Exception: pass
    result = await db.execute(select(Position).where(Position.id == pos_id).options(selectinload(Position.department)))
    return result.scalar_one()

@router.delete("/{pos_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_position(pos_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id))
    db_pos = result.scalar_one_or_none()
    if not db_pos: raise HTTPException(status_code=404, detail="Не найдено")
    try:
        await db.delete(db_pos)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить, есть привязанные сотрудники")

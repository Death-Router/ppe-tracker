from fastapi import APIRouter, Depends, HTTPException, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.department import Department
from app.schemas.department import DepartmentCreate, DepartmentRead, DepartmentUpdate

router = APIRouter(prefix="/departments", tags=["Справочник: Подразделения"])


@router.post("/", response_model=DepartmentRead, status_code=status.HTTP_201_CREATED)
async def create_department(
    dept_in: DepartmentCreate, db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Department).where(Department.name == dept_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Подразделение уже существует")
    db_dept = Department(**dept_in.model_dump())
    db.add(db_dept)
    await db.commit()
    await db.refresh(db_dept)
    return db_dept


@router.get("/", response_model=list[DepartmentRead])
async def get_departments(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department))
    return result.scalars().all()


@router.get("/{dept_id}", response_model=DepartmentRead)
async def get_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept:
        raise HTTPException(status_code=404, detail="Не найдено")
    return dept


@router.put("/{dept_id}", response_model=DepartmentRead)
async def update_department(
    dept_id: int, dept_in: DepartmentUpdate, db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept:
        raise HTTPException(status_code=404, detail="Не найдено")
    if db_dept.version != dept_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    for field, value in dept_in.model_dump(
        exclude_unset=True, exclude={"version"}
    ).items():
        setattr(db_dept, field, value)
    db_dept.version += 1
    await db.commit()
    try:
        await manager.broadcast_to_employee(
            0, {"event": "department_updated", "id": dept_id}
        )
    except (WebSocketDisconnect, RuntimeError) as e:
        print(f"Ошибка WS: {e}")
    return db_dept


@router.delete("/{dept_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept:
        raise HTTPException(status_code=404, detail="Не найдено")
    try:
        await db.delete(db_dept)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400, detail="Нельзя удалить, есть привязанные данные"
        )

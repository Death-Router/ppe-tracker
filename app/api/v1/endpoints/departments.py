from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.department import Department
from app.models.position import Position
from app.models.employee import Employee
from app.schemas.department import DepartmentCreate, DepartmentRead, DepartmentUpdate

router = APIRouter(prefix="/departments", tags=["Справочник: Подразделения"])


async def creates_cycle(db: AsyncSession, dept_id: int, new_parent_id: int) -> bool:
    """Проверяет, не создаст ли смена родителя петлю в дереве.

    Идём от нового родителя вверх по цепочке предков: если встретили само
    подразделение — значит оно уже является его предком, и ссылка замкнёт цикл.
    Ограничение по глубине — страховка от уже испорченных данных.
    """
    seen: set[int] = set()
    current: int | None = new_parent_id
    depth = 0

    while current is not None and depth < 1000:
        if current == dept_id:
            return True
        if current in seen:
            return True
        seen.add(current)

        result = await db.execute(select(Department.parent_id).where(Department.id == current))
        current = result.scalar_one_or_none()
        depth += 1

    return False

@router.post("/", response_model=DepartmentRead, status_code=status.HTTP_201_CREATED)
async def create_department(dept_in: DepartmentCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.name == dept_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Подразделение уже существует")
    
    # Проверка существования родителя
    if dept_in.parent_id:
        parent_res = await db.execute(select(Department).where(Department.id == dept_in.parent_id))
        if not parent_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Вышестоящее подразделение не найдено")

    db_dept = Department(**dept_in.model_dump())
    db.add(db_dept)
    await db.commit()
    await db.refresh(db_dept)
    return db_dept

@router.get("/", response_model=list[DepartmentRead])
async def get_departments(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).options(selectinload(Department.children)))
    return result.scalars().all()

@router.get("/{dept_id}", response_model=DepartmentRead)
async def get_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept: raise HTTPException(status_code=404, detail="Не найдено")
    return dept

@router.put("/{dept_id}", response_model=DepartmentRead)
async def update_department(dept_id: int, dept_in: DepartmentUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept: raise HTTPException(status_code=404, detail="Не найдено")
    if db_dept.version != dept_in.version: raise HTTPException(status_code=409, detail="Данные устарели")
    
    if dept_in.parent_id:
        if dept_in.parent_id == dept_id:
            raise HTTPException(status_code=400, detail="Подразделение не может быть родителем самому себе")
        parent_res = await db.execute(select(Department).where(Department.id == dept_in.parent_id))
        if not parent_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Вышестоящее подразделение не найдено")

        # Проверка «сам себе» не ловит цикл A -> B -> A. Такой цикл вешает
        # рекурсивный обход дочерних подразделений и ломает дерево в UI.
        if await creates_cycle(db, dept_id, dept_in.parent_id):
            raise HTTPException(
                status_code=400,
                detail="Нельзя сделать вышестоящим подразделение, которое уже подчинено этому",
            )
    
    update_data = dept_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_dept, field, value)
    db_dept.version += 1
    await db.commit()
    
    try:
        await manager.broadcast_to_employee(0, {"event": "department_updated", "id": dept_id})
    except: pass
    return db_dept

@router.delete("/{dept_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept: raise HTTPException(status_code=404, detail="Не найдено")

    # Раньше здесь стоял каскад на уровне ORM: одно удаление уносило дочерние
    # подразделения и все должности, не спрашивая. Проверяем явно.
    children = await db.execute(
        select(Department.id).where(Department.parent_id == dept_id).limit(1)
    )
    if children.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="Сначала перенесите или удалите дочерние подразделения",
        )

    positions = await db.execute(
        select(Position.id).where(Position.department_id == dept_id).limit(1)
    )
    if positions.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="В подразделении есть должности — сначала перенесите или удалите их",
        )

    employees = await db.execute(
        select(Employee.id).where(Employee.department_id == dept_id).limit(1)
    )
    if employees.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="В подразделении есть сотрудники — сначала переведите их",
        )

    try:
        await db.delete(db_dept)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить, есть привязанные данные")

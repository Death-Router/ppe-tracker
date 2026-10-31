from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.exc import StaleDataError

from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_item import PpeItem
from app.models.ppe_function import PpeFunction
from app.models.ppe_size_group import PpeSizeGroup
from app.models.department import Department
from app.models.user import User
from app.core.deps import get_current_active_user
from app.schemas.employee import EmployeeCreate, EmployeeRead, EmployeeUpdate

router = APIRouter(prefix="/employees", tags=["Сотрудники"])


def employee_options():
    return [
        selectinload(Employee.ppe_sizes).selectinload(EmployeePpeSize.size_group),
        selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.function),
        selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.size_group),
        selectinload(Employee.department_rel),
        selectinload(Employee.position_rel)
    ]


async def get_employee_with_relations(db: AsyncSession, employee_id: int) -> Employee | None:
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id).options(*employee_options())
    )
    # scalar_one() падал с NoResultFound (500) вместо 404 на несуществующем id
    return result.scalar_one_or_none()


async def get_allowed_department_ids(db: AsyncSession, user: User) -> list[int]:
    """Возвращает список ID подразделений, доступных пользователю (с учётом иерархии)."""
    if user.role == "admin" or not user.department_id:
        return []  # Пустой список = без ограничений (все)

    allowed_ids = [user.department_id]
    
    if user.include_subdepartments:
        # Рекурсивно собираем дочерние подразделения
        result = await db.execute(select(Department))
        all_departments = result.scalars().all()
        
        def collect_children(parent_id):
            children = [d.id for d in all_departments if d.parent_id == parent_id]
            for child in children:
                allowed_ids.append(child)
                collect_children(child)
        
        collect_children(user.department_id)
    
    return allowed_ids


@router.post("/", response_model=EmployeeRead, status_code=status.HTTP_201_CREATED)
async def create_employee(
    employee_in: EmployeeCreate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    if current_user.role == "safety_officer":
        allowed = await get_allowed_department_ids(db, current_user)
        if employee_in.department_id not in allowed:
            raise HTTPException(status_code=403, detail="Вы можете создавать сотрудников только в своем подразделении")

    result = await db.execute(select(Employee).where(Employee.personnel_number == employee_in.personnel_number))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Сотрудник с таким табельным номером уже существует")

    employee_data = employee_in.model_dump(exclude={"ppe_sizes"})
    db_employee = Employee(**employee_data)
    db.add(db_employee)
    await db.flush()

    if employee_in.ppe_sizes:
        cat_ids = [size.size_group_id for size in employee_in.ppe_sizes]
        groups_result = await db.execute(select(PpeSizeGroup.id).where(PpeSizeGroup.id.in_(cat_ids)))
        if set(cat_ids) - set(groups_result.scalars().all()):
            await db.rollback()
            raise HTTPException(status_code=404, detail="Размерные группы не найдены")
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, size_group_id=size_data.size_group_id, size_value=size_data.size_value))

    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "employee_created", "employee_id": db_employee.id})
    except Exception:
        pass

    employee = await get_employee_with_relations(db, db_employee.id)
    if employee is None:
        raise HTTPException(status_code=500, detail="Не удалось прочитать созданного сотрудника")
    return employee


@router.get("/", response_model=list[EmployeeRead])
async def get_employees(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(Employee).options(*employee_options())
    
    allowed = await get_allowed_department_ids(db, current_user)
    if allowed:
        query = query.where(Employee.department_id.in_(allowed))

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{employee_id}", response_model=EmployeeRead)
async def get_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    employee = await get_employee_with_relations(db, employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    
    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    return employee


@router.put("/{employee_id}", response_model=EmployeeRead)
async def update_employee(
    employee_id: int, 
    employee_in: EmployeeUpdate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    db_employee = result.scalar_one_or_none()
    if not db_employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and db_employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    if db_employee.version != employee_in.version:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Данные устарели")

    update_data = employee_in.model_dump(exclude_unset=True, exclude={"version", "ppe_sizes"})
    for field, value in update_data.items():
        setattr(db_employee, field, value)

    # Без инкремента проверка версии выше пропускала бы любые параллельные правки
    db_employee.version += 1

    if employee_in.ppe_sizes is not None:
        await db.execute(delete(EmployeePpeSize).where(EmployeePpeSize.employee_id == employee_id))
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, size_group_id=size_data.size_group_id, size_value=size_data.size_value))

    try:
        await db.commit()
    except StaleDataError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Конфликт версий")

    try:
        await manager.broadcast_to_employee(employee_id, {"event": "employee_updated", "employee_id": employee_id})
    except Exception:
        pass

    employee = await get_employee_with_relations(db, employee_id)
    if employee is None:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    return employee


@router.delete("/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    db_employee = result.scalar_one_or_none()
    if not db_employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and db_employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    try:
        await db.delete(db_employee)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")

    try:
        await manager.broadcast_to_employee(0, {"event": "employee_updated", "employee_id": employee_id})
    except Exception:
        pass

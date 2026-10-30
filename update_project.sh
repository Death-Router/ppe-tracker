#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем employees.py (заменяем category на size_group)..."

cat > app/api/v1/endpoints/employees.py << 'EOF'
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
from app.models.ppe_size_group import PpeSizeGroup
from app.models.user import User
from app.core.deps import get_current_active_user
from app.schemas.employee import EmployeeCreate, EmployeeRead, EmployeeUpdate

router = APIRouter(prefix="/employees", tags=["Сотрудники"])


def employee_options():
    return [
        # Размеры сотрудника (привязаны к размерным группам)
        selectinload(Employee.ppe_sizes).selectinload(EmployeePpeSize.size_group),
        # Выдачи (привязаны к СИЗ)
        selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.function),
        selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.size_group),
        # Подразделение и должность
        selectinload(Employee.department_rel),
        selectinload(Employee.position_rel)
    ]


async def get_employee_with_relations(db: AsyncSession, employee_id: int) -> Employee:
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id).options(*employee_options())
    )
    return result.scalar_one()


@router.post("/", response_model=EmployeeRead, status_code=status.HTTP_201_CREATED)
async def create_employee(
    employee_in: EmployeeCreate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    if current_user.role == "safety_officer":
        if current_user.department_id != employee_in.department_id:
            raise HTTPException(status_code=403, detail="Вы можете создавать сотрудников только в своем подразделении")

    result = await db.execute(select(Employee).where(Employee.personnel_number == employee_in.personnel_number))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Сотрудник с таким табельным номером уже существует")

    employee_data = employee_in.model_dump(exclude={"ppe_sizes"})
    db_employee = Employee(**employee_data)
    db.add(db_employee)
    await db.flush()

    if employee_in.ppe_sizes:
        size_group_ids = [size.size_group_id for size in employee_in.ppe_sizes]
        groups_result = await db.execute(select(PpeSizeGroup.id).where(PpeSizeGroup.id.in_(size_group_ids)))
        if set(size_group_ids) - set(groups_result.scalars().all()):
            await db.rollback()
            raise HTTPException(status_code=404, detail="Размерные группы не найдены")
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, size_group_id=size_data.size_group_id, size_value=size_data.size_value))

    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "employee_created", "employee_id": db_employee.id})
    except Exception:
        pass

    return await get_employee_with_relations(db, db_employee.id)


@router.get("/", response_model=list[EmployeeRead])
async def get_employees(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(Employee).options(*employee_options())
    
    if current_user.role == "safety_officer" and current_user.department_id:
        query = query.where(Employee.department_id == current_user.department_id)

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
    
    if current_user.role == "safety_officer" and current_user.department_id != employee.department_id:
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

    if current_user.role == "safety_officer" and current_user.department_id != db_employee.department_id:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    if db_employee.version != employee_in.version:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Данные устарели")

    update_data = employee_in.model_dump(exclude_unset=True, exclude={"version", "ppe_sizes"})
    for field, value in update_data.items():
        setattr(db_employee, field, value)

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

    return await get_employee_with_relations(db, employee_id)


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

    if current_user.role == "safety_officer" and current_user.department_id != db_employee.department_id:
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
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Ошибка с category исправлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: replace category with size_group in employee sizes"
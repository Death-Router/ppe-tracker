from fastapi import APIRouter, Depends, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db.session import get_db
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.position import Position
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.ppe_item import PpeItem
from app.utils.excel import generate_excel

router = APIRouter(prefix="/export", tags=["Экспорт данных"])

@router.get("/employees")
async def export_employees(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Employee).options(
            selectinload(Employee.department_rel),
            selectinload(Employee.position_rel),
            selectinload(Employee.ppe_sizes).selectinload(EmployeePpeSize.size_group)
        )
    )
    employees = result.scalars().all()

    data = []
    for emp in employees:
        sizes_str = ", ".join([f"{s.size_group.name}: {s.size_value}" for s in emp.ppe_sizes]) if emp.ppe_sizes else ""
        
        data.append({
            "Табельный номер": emp.personnel_number,
            "Фамилия": emp.last_name,
            "Имя": emp.first_name,
            "Отчество": emp.middle_name or "",
            "Подразделение": emp.department_rel.name if emp.department_rel else "",
            "Должность": emp.position_rel.name if emp.position_rel else "",
            "Дата приема": emp.hire_date.strftime("%d.%m.%Y") if emp.hire_date else "",
            "Пол": emp.gender or "",
            "Рост": emp.height or "",
            "Размеры СИЗ": sizes_str
        })

    file = generate_excel(data, "employees")
    return Response(
        content=file.read(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=employees.xlsx"}
    )

@router.get("/ppe-items")
async def export_ppe_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PpeItem).options(
            selectinload(PpeItem.function),
            selectinload(PpeItem.size_group),
            selectinload(PpeItem.unit)
        )
    )
    items = result.scalars().all()

    data = []
    for item in items:
        data.append({
            "Наименование": item.name,
            "Функция": item.function.name if item.function else "",
            "Размерная группа": item.size_group.name if item.size_group else "",
            "Единица измерения": item.unit.short_name if item.unit else ""
        })

    file = generate_excel(data, "ppe_items")
    return Response(
        content=file.read(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=ppe_items.xlsx"}
    )

@router.get("/norms")
async def export_norms(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PositionPpeNorm).options(
            selectinload(PositionPpeNorm.position).selectinload(Position.department),
            selectinload(PositionPpeNorm.ppe_item)
        )
    )
    norms = result.scalars().all()

    data = []
    for norm in norms:
        data.append({
            "Подразделение": norm.position.department.name if norm.position and norm.position.department else "",
            "Должность": norm.position.name if norm.position else "",
            "СИЗ": norm.ppe_item.name if norm.ppe_item else "",
            "Срок": f"{norm.wear_period_value} {norm.wear_period_unit}" if norm.wear_period_value else "",
            "Количество": norm.quantity or ""
        })

    file = generate_excel(data, "norms")
    return Response(
        content=file.read(),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": "attachment; filename=norms.xlsx"}
    )

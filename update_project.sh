#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Перезаписываем employee_ppe_issues.py (function и size_group)..."

cat > app/api/v1/endpoints/employee_ppe_issues.py << 'EOF'
from datetime import date, timedelta
from fastapi import APIRouter, Depends, HTTPException, status, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.employee import Employee
from app.models.ppe_item import PpeItem
from app.models.position_ppe_norm import PositionPpeNorm
from app.schemas.employee_ppe_issue import EmployeePpeIssueCreate, EmployeePpeIssueRead

router = APIRouter(prefix="/employee_ppe_issues", tags=["Выдача СИЗ"])


@router.post("/", response_model=EmployeePpeIssueRead, status_code=status.HTTP_201_CREATED)
async def create_issue(issue_in: EmployeePpeIssueCreate, db: AsyncSession = Depends(get_db)):
    # 1. Проверяем сотрудника
    emp_res = await db.execute(select(Employee).where(Employee.id == issue_in.employee_id))
    employee = emp_res.scalar_one_or_none()
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    # 2. Проверяем СИЗ
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == issue_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    # 3. Рассчитываем срок годности на основе нормы
    expiry_date = None
    if employee.position_id:
        norm_res = await db.execute(
            select(PositionPpeNorm).where(
                PositionPpeNorm.position_id == employee.position_id,
                PositionPpeNorm.ppe_item_id == issue_in.ppe_item_id
            )
        )
        norm = norm_res.scalar_one_or_none()
        if norm and norm.wear_period_unit in ('год', 'месяц'):
            try:
                val = int(norm.wear_period_value)
                if norm.wear_period_unit == 'год':
                    expiry_date = issue_in.issue_date + timedelta(days=365 * val)
                elif norm.wear_period_unit == 'месяц':
                    expiry_date = issue_in.issue_date + timedelta(days=30 * val)
            except ValueError:
                pass

    # 4. Создаем запись
    db_issue = EmployeePpeIssue(
        employee_id=issue_in.employee_id,
        ppe_item_id=issue_in.ppe_item_id,
        issue_date=issue_in.issue_date,
        quantity=issue_in.quantity,
        size_value=issue_in.size_value,
        expiry_date=expiry_date
    )
    db.add(db_issue)
    await db.commit()
    await db.refresh(db_issue)

    # 5. Загружаем связи для ответа
    result = await db.execute(
        select(EmployeePpeIssue).where(EmployeePpeIssue.id == db_issue.id)
        .options(selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.function),
                 selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.size_group))
    )
    return result.scalar_one()


@router.get("/", response_model=list[EmployeePpeIssueRead])
async def get_issues(employee_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(EmployeePpeIssue).where(EmployeePpeIssue.employee_id == employee_id)
        .options(selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.function),
                 selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.size_group))
    )
    return result.scalars().all()


@router.delete("/{issue_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_issue(issue_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(EmployeePpeIssue).where(EmployeePpeIssue.id == issue_id))
    db_issue = result.scalar_one_or_none()
    if not db_issue:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    try:
        await db.delete(db_issue)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")

    try:
        await manager.broadcast_to_employee(0, {"event": "issue_updated", "employee_id": db_issue.employee_id})
    except: pass
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! API выдач обновлено (function и size_group)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: update employee_ppe_issues API for function/size_group"
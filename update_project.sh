#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем модель для выдачи СИЗ..."

cat > app/models/employee_ppe_issue.py << 'EOF'
from datetime import date
from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, Date
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.ppe_item import PpeItem

class EmployeePpeIssue(Base):
    __tablename__ = "employee_ppe_issues"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id", ondelete="CASCADE"))
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    
    issue_date: Mapped[date] = mapped_column(Date, nullable=False)
    quantity: Mapped[str] = mapped_column(String(50), default="1")
    size_value: Mapped[str | None] = mapped_column(String(50), nullable=True)
    
    # Дата окончания срока носки (рассчитывается автоматически)
    expiry_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    employee: Mapped["Employee"] = relationship(back_populates="ppe_issues")
    ppe_item: Mapped["PpeItem"] = relationship(back_populates="employee_issues")
EOF

echo "🔧 Обновляем связи в моделях Employee и PpeItem..."

python3 - << 'PYEOF'
# Добавляем связь в Employee
with open('app/models/employee.py', 'r') as f:
    content = f.read()

if 'ppe_issues' not in content:
    content = content.replace(
        'ppe_sizes: Mapped[list["EmployeePpeSize"]] = relationship(back_populates="employee", cascade="all, delete-orphan")',
        'ppe_sizes: Mapped[list["EmployeePpeSize"]] = relationship(back_populates="employee", cascade="all, delete-orphan")\n    ppe_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="employee", cascade="all, delete-orphan")'
    )
    content = content.replace(
        'from app.models.employee_ppe_size import EmployeePpeSize',
        'from app.models.employee_ppe_size import EmployeePpeSize\n    from app.models.employee_ppe_issue import EmployeePpeIssue'
    )
    with open('app/models/employee.py', 'w') as f:
        f.write(content)
    print("✅ Связь добавлена в Employee.")

# Добавляем связь в PpeItem
with open('app/models/ppe_item.py', 'r') as f:
    content = f.read()

if 'employee_issues' not in content:
    content = content.replace(
        'position_norms: Mapped[list["PositionPpeNorm"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")',
        'position_norms: Mapped[list["PositionPpeNorm"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")\n    employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")'
    )
    content = content.replace(
        'from app.models.position_ppe_norm import PositionPpeNorm',
        'from app.models.position_ppe_norm import PositionPpeNorm\n    from app.models.employee_ppe_issue import EmployeePpeIssue'
    )
    with open('app/models/ppe_item.py', 'w') as f:
        f.write(content)
    print("✅ Связь добавлена в PpeItem.")
PYEOF

echo "🔧 Обновляем base.py для Alembic..."

cat > app/db/base.py << 'EOF'
from sqlalchemy.orm import DeclarativeBase

class Base(DeclarativeBase):
    pass

# Импортируем все модели, чтобы Alembic видел их при миграциях
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.department import Department
from app.models.position import Position
from app.models.position_ppe_norm import PositionPpeNorm
EOF

echo "📝 Создаем схемы для выдачи..."

cat > app/schemas/employee_ppe_issue.py << 'EOF'
from datetime import date
from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_item import PpeItemRead

class EmployeePpeIssueBase(BaseModel):
    employee_id: int
    ppe_item_id: int
    issue_date: date
    quantity: str = Field("1", max_length=50)
    size_value: str | None = Field(None, max_length=50)

class EmployeePpeIssueCreate(EmployeePpeIssueBase):
    pass

class EmployeePpeIssueRead(EmployeePpeIssueBase):
    id: int
    version: int
    expiry_date: date | None = None
    ppe_item: PpeItemRead | None = None
    model_config = ConfigDict(from_attributes=True)
EOF

echo "📝 Создаем API для выдачи..."

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
        .options(selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.category))
    )
    return result.scalar_one()


@router.get("/", response_model=list[EmployeePpeIssueRead])
async def get_issues(employee_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(EmployeePpeIssue).where(EmployeePpeIssue.employee_id == employee_id)
        .options(selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.category))
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

echo "🔧 Подключаем роутер в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'employee_ppe_issues' not in content:
    content = content.replace(
        'from app.api.v1.endpoints import employees, ppe_categories, ppe_items, ws, departments, positions, position_ppe_norms',
        'from app.api.v1.endpoints import employees, ppe_categories, ppe_items, ws, departments, positions, position_ppe_norms, employee_ppe_issues'
    )
    content = content.replace(
        'app.include_router(position_ppe_norms.router, prefix="/api/v1")',
        'app.include_router(position_ppe_norms.router, prefix="/api/v1")\napp.include_router(employee_ppe_issues.router, prefix="/api/v1")'
    )
with open('app/main.py', 'w') as f:
    f.write(content)
print("✅ main.py обновлен.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "add employee_ppe_issues table"

echo "🔄 Применяем миграцию..."
docker compose exec -T api alembic upgrade head

echo "📝 Добавляем блок 'Выданные СИЗ' в карточку сотрудника..."

# Обновляем edit.html
python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Ищем место после блока размеров СИЗ и перед кнопками сохранения
marker = '''            <div class="d-flex justify-content-end gap-2 mt-4">'''

new_block = '''
            <hr class="my-4">
            
            <div class="d-flex justify-content-between align-items-center mb-3">
                <h5 class="mb-0 text-secondary">Выданные СИЗ</h5>
                <button type="button" class="btn btn-sm btn-outline-primary" data-bs-toggle="modal" data-bs-target="#issueModal">+ Выдать СИЗ</button>
            </div>
            
            <div class="table-responsive mb-4">
                <table class="table table-sm table-bordered align-middle" id="issues-table">
                    <thead class="bg-brand-orange">
                        <tr>
                            <th>СИЗ</th>
                            <th>Дата выдачи</th>
                            <th>Срок годности</th>
                            <th>Кол-во</th>
                            <th style="width: 60px;" class="text-center"></th>
                        </tr>
                    </thead>
                    <tbody>
                        <!-- Заполняется через JS -->
                    </tbody>
                </table>
            </div>
'''

content = content.replace(marker, new_block + marker)

# Добавляем модальное окно выдачи в конец блока контента
modal_html = '''
<!-- Модальное окно выдачи -->
<div class="modal fade" id="issueModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="issue-form">
        <div class="modal-header">
          <h5 class="modal-title">Выдача СИЗ</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
            <div class="mb-3">
                <label class="form-label">Наименование СИЗ <span class="text-danger">*</span></label>
                <select class="form-select" name="ppe_item_id" id="issue-item-select" required>
                    <option value="">Загрузка...</option>
                </select>
            </div>
            <div class="row g-3">
                <div class="col-6">
                    <label class="form-label">Дата выдачи <span class="text-danger">*</span></label>
                    <input type="date" class="form-control" name="issue_date" required value="2026-10-29">
                </div>
                <div class="col-6">
                    <label class="form-label">Количество <span class="text-danger">*</span></label>
                    <input type="text" class="form-control" name="quantity" required value="1">
                </div>
            </div>
            <div class="mb-3 mt-3">
                <label class="form-label">Размер (опционально)</label>
                <input type="text" class="form-control" name="size_value" placeholder="Например, 42">
            </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-primary">Выдать</button>
        </div>
      </form>
    </div>
  </div>
</div>
'''

# Вставляем перед {% endblock %} (перед закрытием блока content)
content = content.replace('{% endblock %}', modal_html + '\n{% endblock %}')

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
print("✅ Блок выдачи добавлен в edit.html.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Модель, API и интерфейс для выдачи созданы."

# --- Git Commit (как договорились) ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add employee PPE issues (backend model, API, UI block and modal)"
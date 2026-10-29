#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем модель для справочника размеров..."

cat > app/models/ppe_size.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_item import PpeItem

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("ppe_item_id", "size_value", name="uq_ppe_item_size"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)

    ppe_item: Mapped["PpeItem"] = relationship(back_populates="sizes")
EOF

echo "🔧 Обновляем связи в PpeItem..."

python3 - << 'PYEOF'
with open('app/models/ppe_item.py', 'r') as f:
    content = f.read()

if 'sizes: Mapped' not in content:
    content = content.replace(
        'employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")',
        'employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")\n    sizes: Mapped[list["PpeSize"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")'
    )
    content = content.replace(
        'from app.models.employee_ppe_issue import EmployeePpeIssue',
        'from app.models.employee_ppe_issue import EmployeePpeIssue\n    from app.models.ppe_size import PpeSize'
    )
    with open('app/models/ppe_item.py', 'w') as f:
        f.write(content)
    print("✅ Связь sizes добавлена в PpeItem.")
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
from app.models.ppe_size import PpeSize
from app.models.department import Department
from app.models.position import Position
from app.models.position_ppe_norm import PositionPpeNorm
EOF

echo "📝 Создаем схемы для размеров..."

cat > app/schemas/ppe_size.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class PpeSizeBase(BaseModel):
    ppe_item_id: int
    size_value: str = Field(..., max_length=50)

class PpeSizeCreate(PpeSizeBase):
    pass

class PpeSizeRead(PpeSizeBase):
    id: int
    model_config = ConfigDict(from_attributes=True)
EOF

echo "📝 Создаем API для размеров..."

cat > app/api/v1/endpoints/ppe_sizes.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.ppe_size import PpeSize
from app.models.ppe_item import PpeItem
from app.schemas.ppe_size import PpeSizeCreate, PpeSizeRead

router = APIRouter(prefix="/ppe_sizes", tags=["Справочник: Размеры СИЗ"])

@router.post("/", response_model=PpeSizeRead, status_code=status.HTTP_201_CREATED)
async def create_size(size_in: PpeSizeCreate, db: AsyncSession = Depends(get_db)):
    # Проверяем, существует ли СИЗ
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == size_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    db_size = PpeSize(**size_in.model_dump())
    db.add(db_size)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такой размер уже существует для этого СИЗ")
    
    await db.refresh(db_size)
    return db_size

@router.get("/", response_model=list[PpeSizeRead])
async def get_sizes(ppe_item_id: int | None = None, db: AsyncSession = Depends(get_db)):
    query = select(PpeSize)
    if ppe_item_id is not None:
        query = query.where(PpeSize.ppe_item_id == ppe_item_id)
    result = await db.execute(query)
    return result.scalars().all()

@router.delete("/{size_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_size(size_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSize).where(PpeSize.id == size_id))
    db_size = result.scalar_one_or_none()
    if not db_size:
        raise HTTPException(status_code=404, detail="Размер не найден")
    await db.delete(db_size)
    await db.commit()
EOF

echo "🔧 Подключаем роутер в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'ppe_sizes' not in content.split('app.include_router')[0]:
    # Добавляем в импорт
    if 'employee_ppe_issues' in content:
        content = content.replace(
            'employee_ppe_issues',
            'employee_ppe_issues, ppe_sizes'
        )
    # Добавляем include_router
    content = content.replace(
        'app.include_router(employee_ppe_issues.router, prefix="/api/v1")',
        'app.include_router(employee_ppe_issues.router, prefix="/api/v1")\napp.include_router(ppe_sizes.router, prefix="/api/v1")'
    )
with open('app/main.py', 'w') as f:
    f.write(content)
print("✅ main.py обновлен.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "add ppe_sizes table"

echo "🔄 Применяем миграцию..."
docker compose exec -T api alembic upgrade head

echo "📝 Обновляем интерфейс списка СИЗ (кнопка 'Размеры' и модалка)..."

# Обновляем ppe_items/list.html
python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Добавляем кнопку "Размеры" в строку таблицы (в JS) и модалку в HTML
# Сначала добавим модалку в конец блока content (перед {% endblock %})
modal_html = '''
<!-- Модальное окно управления размерами -->
<div class="modal fade" id="sizesModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="size-form">
        <input type="hidden" name="ppe_item_id" id="size-item-id">
        <div class="modal-header">
          <h5 class="modal-title">Размеры для: <span id="size-item-name"></span></h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
            <div class="mb-3">
                <label class="form-label">Новый размер</label>
                <div class="input-group">
                    <input type="text" class="form-control" name="size_value" placeholder="Например, 42 или M" required>
                    <button class="btn btn-primary" type="submit">Добавить</button>
                </div>
            </div>
            <ul class="list-group" id="sizes-list">
                <!-- Список размеров -->
            </ul>
        </div>
      </form>
    </div>
  </div>
</div>
'''
content = content.replace('{% endblock %}', modal_html + '\n{% endblock %}')
with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
print("✅ Модалка размеров добавлена в list.html.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Модель, API и модалка для размеров созданы."
echo "⚠️ Осталось добавить JS-логику в ppe_items_list.js (следующий скрипт)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add ppe_sizes model, API and modal for managing sizes"
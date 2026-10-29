#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем модель PpeSize (добавляем поле gender)..."

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
        UniqueConstraint("ppe_item_id", "size_value", "gender", name="uq_ppe_item_size_gender"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True, comment="М, Ж или NULL (унисекс)")

    ppe_item: Mapped["PpeItem"] = relationship(back_populates="sizes")
EOF

echo "📝 Обновляем схемы..."

cat > app/schemas/ppe_size.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class PpeSizeBase(BaseModel):
    ppe_item_id: int
    size_value: str = Field(..., max_length=50)
    gender: str | None = Field(None, pattern="^[МЖ]$")

class PpeSizeCreate(PpeSizeBase):
    pass

class PpeSizeRead(PpeSizeBase):
    id: int
    model_config = ConfigDict(from_attributes=True)
EOF

echo "📝 Обновляем API (учет пола)..."

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
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == size_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    db_size = PpeSize(**size_in.model_dump())
    db.add(db_size)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такой размер (с учетом пола) уже существует для этого СИЗ")
    
    await db.refresh(db_size)
    return db_size

@router.get("/", response_model=list[PpeSizeRead])
async def get_sizes(ppe_item_id: int | None = None, gender: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(PpeSize)
    if ppe_item_id is not None:
        query = query.where(PpeSize.ppe_item_id == ppe_item_id)
    if gender:
        query = query.where(PpeSize.gender == gender)
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

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию для поля gender..."
docker compose exec -T api alembic revision --autogenerate -m "add gender to ppe_sizes"
docker compose exec -T api alembic upgrade head

echo "📝 Обновляем JS для размеров (учет пола)..."

# Обновляем ppe_items_list.js — добавляем поле пола в форму
python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# В функции renderSizesList добавляем отображение пола
old_render = '''    sizesList.innerHTML = sizes.map(s => `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        ${escapeHtml(s.size_value)}
        <button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `).join('');'''

new_render = '''    sizesList.innerHTML = sizes.map(s => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `}).join('');'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ Отображение пола добавлено в список размеров.")
else:
    print("⚠️ Не удалось найти блок renderSizesList.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Обновляем форму добавления размера (добавляем выбор пола)..."

# Обновляем модалку в ppe_items/list.html — добавляем select для пола
python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

old_input_group = '''                <div class="input-group">
                    <input type="text" class="form-control" name="size_value" placeholder="Например, 42 или M" required>
                    <button class="btn btn-primary" type="submit">Добавить</button>
                </div>'''

new_input_group = '''                <div class="row g-2">
                    <div class="col-4">
                        <select class="form-select" name="gender">
                            <option value="">Унисекс</option>
                            <option value="М">Мужской</option>
                            <option value="Ж">Женский</option>
                        </select>
                    </div>
                    <div class="col-5">
                        <input type="text" class="form-control" name="size_value" placeholder="Например, 42" required>
                    </div>
                    <div class="col-3">
                        <button class="btn btn-primary w-100" type="submit">Добавить</button>
                    </div>
                </div>'''

if old_input_group in content:
    content = content.replace(old_input_group, new_input_group)
    print("✅ Форма добавления размера обновлена (выбор пола).")
else:
    print("⚠️ Не удалось найти форму добавления размера.")

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
PYEOF

# Обновляем JS для отправки поля gender
python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

old_submit = '''      await API.post('/api/v1/ppe_sizes/', { ppe_item_id: itemId, size_value: sizeValue });'''
new_submit = '''      const gender = sizeForm.elements['gender'].value || null;
      await API.post('/api/v1/ppe_sizes/', { ppe_item_id: itemId, size_value: sizeValue, gender: gender });'''

if old_submit in content:
    content = content.replace(old_submit, new_submit)
    print("✅ Отправка gender добавлена в JS.")
else:
    print("⚠️ Не удалось найти блок отправки размера.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Поле пола добавлено в справочник размеров."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add gender field to ppe_sizes and update UI"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем схемы PpeItem (добавляем unit_id)..."

cat > app/schemas/ppe_item.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_category import PpeCategoryRead

class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=255, description="Наименование СИЗ")
    category_id: int = Field(..., description="ID категории")
    unit_id: int | None = Field(None, description="ID единицы измерения")

class PpeItemCreate(PpeItemBase):
    pass

class PpeItemRead(PpeItemBase):
    id: int
    version: int
    category: PpeCategoryRead | None = None
    unit: dict | None = None
    model_config = ConfigDict(from_attributes=True)

class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=255)
    category_id: int | None = None
    unit_id: int | None = None
    version: int
EOF

echo "🔧 Обновляем API ppe_items (сохранение unit_id)..."

cat > app/api/v1/endpoints/ppe_items.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.ppe_item import PpeItem
from app.models.ppe_category import PpeCategory
from app.models.unit import Unit
from app.schemas.ppe_item import PpeItemCreate, PpeItemRead, PpeItemUpdate

router = APIRouter(prefix="/ppe_items", tags=["Справочник: Наименования СИЗ"])

@router.post("/", response_model=PpeItemRead, status_code=status.HTTP_201_CREATED)
async def create_item(item_in: PpeItemCreate, db: AsyncSession = Depends(get_db)):
    cat_res = await db.execute(select(PpeCategory).where(PpeCategory.id == item_in.category_id))
    if not cat_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Категория не найдена")

    db_item = PpeItem(**item_in.model_dump())
    db.add(db_item)
    await db.commit()
    await db.refresh(db_item)
    
    result = await db.execute(
        select(PpeItem).where(PpeItem.id == db_item.id)
        .options(selectinload(PpeItem.category), selectinload(PpeItem.unit))
    )
    return result.scalar_one()

@router.get("/", response_model=list[PpeItemRead])
async def get_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).options(selectinload(PpeItem.category), selectinload(PpeItem.unit)))
    return result.scalars().all()

@router.get("/{item_id}", response_model=PpeItemRead)
async def get_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PpeItem).where(PpeItem.id == item_id)
        .options(selectinload(PpeItem.category), selectinload(PpeItem.unit))
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")
    return item

@router.put("/{item_id}", response_model=PpeItemRead)
async def update_item(item_id: int, item_in: PpeItemUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    if db_item.version != item_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")

    update_data = item_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_item, field, value)
    db_item.version += 1
    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "item_updated", "item_id": item_id})
    except Exception:
        pass

    result = await db.execute(
        select(PpeItem).where(PpeItem.id == item_id)
        .options(selectinload(PpeItem.category), selectinload(PpeItem.unit))
    )
    return result.scalar_one()

@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")
    try:
        await db.delete(db_item)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Теперь unit_id сохраняется."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: save unit_id in ppe_items update and schema"
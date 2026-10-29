#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно перезаписываем app/schemas/ppe_item.py..."

cat > app/schemas/ppe_item.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_category import PpeCategoryRead
from app.schemas.unit import UnitRead

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
    unit: UnitRead | None = None
    model_config = ConfigDict(from_attributes=True)

class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=255)
    category_id: int | None = None
    unit_id: int | None = None
    version: int
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Схема исправлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force correct unit type in PpeItemRead schema"
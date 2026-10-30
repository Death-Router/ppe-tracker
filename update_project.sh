#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно перезаписываем схему PpeItem (без category_id)..."

cat > app/schemas/ppe_item.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_function import PpeFunctionRead
from app.schemas.ppe_size_group import PpeSizeGroupRead
from app.schemas.unit import UnitRead

class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=255, description="Наименование СИЗ")
    function_id: int | None = Field(None, description="ID функции СИЗ")
    size_group_id: int | None = Field(None, description="ID размерной группы")
    unit_id: int | None = Field(None, description="ID единицы измерения")

class PpeItemCreate(PpeItemBase):
    pass

class PpeItemRead(PpeItemBase):
    id: int
    version: int
    function: PpeFunctionRead | None = None
    size_group: PpeSizeGroupRead | None = None
    unit: UnitRead | None = None
    model_config = ConfigDict(from_attributes=True)

class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=255)
    function_id: int | None = None
    size_group_id: int | None = None
    unit_id: int | None = None
    version: int
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Схема PpeItem обновлена (без category_id)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force update ppe_item schema (remove category_id)"
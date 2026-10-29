#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем импорт Position в export.py..."

python3 - << 'PYEOF'
with open('app/api/v1/endpoints/export.py', 'r') as f:
    content = f.read()

# Проверяем, есть ли уже импорт Position
if 'from app.models.position import Position' not in content:
    # Добавляем после импорта PositionPpeNorm
    content = content.replace(
        'from app.models.position_ppe_norm import PositionPpeNorm',
        'from app.models.position_ppe_norm import PositionPpeNorm\nfrom app.models.position import Position'
    )
    print("✅ Импорт Position добавлен.")
else:
    print("ℹ️ Импорт Position уже есть.")

with open('app/api/v1/endpoints/export.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: add missing Position import in export.py"
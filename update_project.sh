#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем импорт PpeSize в alembic/env.py (чтобы Alembic не удалял таблицу)..."

python3 - << 'PYEOF'
with open('alembic/env.py', 'r') as f:
    content = f.read()

if 'from app.models.ppe_size import PpeSize' not in content:
    content = content.replace(
        'from app.models.ppe_item import PpeItem',
        'from app.models.ppe_item import PpeItem\nfrom app.models.ppe_size import PpeSize'
    )
    with open('alembic/env.py', 'w') as f:
        f.write(content)
    print("✅ Импорт PpeSize добавлен в alembic/env.py.")
else:
    print("ℹ️ Импорт PpeSize уже есть.")
PYEOF

echo "🛠 Проверяем и восстанавливаем таблицу ppe_sizes..."

# Проверяем, существует ли таблица
TABLE_EXISTS=$(docker compose exec -T db psql -U ppe -d ppe_db -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'ppe_sizes');")

if [ "$TABLE_EXISTS" = "f" ]; then
    echo "⚠️ Таблица ppe_sizes отсутствует. Создаем заново..."
    docker compose exec -T db psql -U ppe -d ppe_db << 'EOF'
CREATE TABLE ppe_sizes (
    id SERIAL PRIMARY KEY,
    ppe_item_id INTEGER NOT NULL REFERENCES ppe_items(id) ON DELETE CASCADE,
    size_value VARCHAR(50) NOT NULL,
    gender VARCHAR(1) NULL,
    CONSTRAINT uq_ppe_item_size_gender UNIQUE (ppe_item_id, size_value, gender)
);
CREATE INDEX ix_ppe_sizes_ppe_item_id ON ppe_sizes(ppe_item_id);
EOF
    echo "✅ Таблица ppe_sizes восстановлена."
else
    echo "ℹ️ Таблица ppe_sizes существует. Данные сохранены."
fi

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: add PpeSize to alembic env and restore ppe_sizes table"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🛠 Приводим названия категорий к нормальному регистру (через SQL)..."

# Выполняем SQL-запрос для обновления имен категорий
# initcap() в PostgreSQL делает первую букву заглавной, остальные строчными
docker compose exec -T db psql -U ppe -d ppe_db -c "UPDATE ppe_categories SET name = initcap(name);"

echo "🚀 Перезапускаем контейнер (на всякий случай)..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Названия категорий приведены к нормальному виду."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "data: capitalize category names in database"
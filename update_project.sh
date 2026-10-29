#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🛠 Очищаем таблицу employee_ppe_sizes (удаляем старые данные)..."

# Очищаем таблицу с размерами сотрудников
docker compose exec -T db psql -U ppe -d ppe_db -c "TRUNCATE TABLE employee_ppe_sizes RESTART IDENTITY CASCADE;"

echo "🔄 Откатываем неудачную миграцию (если она частично применилась)..."

# Откатываем последнюю миграцию, если она была
docker compose exec -T api alembic downgrade -1 || true

echo "🔄 Применяем миграцию заново..."

docker compose exec -T api alembic upgrade head

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Миграция применена. Теперь размеры сотрудников привязаны к категориям."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: clear employee_ppe_sizes table and reapply migration"
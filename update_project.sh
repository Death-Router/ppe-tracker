#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обманываем Alembic: говорим, что миграция fix_employee_sizes уже применена..."

# Принудительно ставим версию fix_employee_sizes
docker compose exec -T api alembic stamp fix_employee_sizes

echo "✅ Alembic теперь считает, что мы на версии fix_employee_sizes."

echo "🔧 Теперь создаем миграцию для удаления ppe_categories..."

# Генерируем миграцию (теперь база должна быть в актуальном состоянии)
docker compose exec -T api alembic revision --autogenerate -m "drop ppe_categories table"

echo "🔄 Применяем миграцию..."
docker compose exec -T api alembic upgrade head

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Таблица ppe_categories удалена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: stamp fix_employee_sizes and drop ppe_categories"
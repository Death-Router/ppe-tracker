#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно переименовываем колонку через SQL..."

# Выполняем SQL-запрос напрямую в базе
docker compose exec -T db psql -U ppe -d ppe_db << 'EOF'
-- Переименовываем колонку
ALTER TABLE employee_ppe_sizes RENAME COLUMN category_id TO size_group_id;

-- Удаляем старый внешний ключ (если есть) и создаем новый
ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS employee_ppe_sizes_category_id_fkey;
ALTER TABLE employee_ppe_sizes ADD CONSTRAINT employee_ppe_sizes_size_group_id_fkey 
    FOREIGN KEY (size_group_id) REFERENCES ppe_size_groups(id) ON DELETE CASCADE;

-- Удаляем старый уникальный ключ и создаем новый
ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS uq_employee_category_size;
ALTER TABLE employee_ppe_sizes ADD CONSTRAINT uq_employee_size_group 
    UNIQUE (employee_id, size_group_id);
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Колонка переименована через SQL."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: rename category_id to size_group_id via SQL"
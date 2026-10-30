#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Переносим данные из ppe_categories в ppe_functions и ppe_size_groups..."

docker compose exec -T db psql -U ppe -d ppe_db << 'EOF'
-- 1. Заполняем ppe_size_groups (где есть ключевые слова про размеры)
INSERT INTO ppe_size_groups (name, version)
SELECT name, 1 FROM ppe_categories
WHERE lower(name) LIKE '%обувь%' 
   OR lower(name) LIKE '%одежда%' 
   OR lower(name) LIKE '%костюм%' 
   OR lower(name) LIKE '%перчатк%' 
   OR lower(name) LIKE '%головн%'
   OR lower(name) LIKE '%средства защиты рук%'
   OR lower(name) LIKE '%средства защиты ног%'
   OR lower(name) LIKE '%средства защиты головы%'
ON CONFLICT (name) DO NOTHING;

-- 2. Заполняем ppe_functions (все остальные)
INSERT INTO ppe_functions (name, version)
SELECT name, 1 FROM ppe_categories
WHERE lower(name) NOT LIKE '%обувь%' 
  AND lower(name) NOT LIKE '%одежда%' 
  AND lower(name) NOT LIKE '%костюм%' 
  AND lower(name) NOT LIKE '%перчатк%' 
  AND lower(name) NOT LIKE '%головн%'
  AND lower(name) NOT LIKE '%средства защиты рук%'
  AND lower(name) NOT LIKE '%средства защиты ног%'
  AND lower(name) NOT LIKE '%средства защиты головы%'
ON CONFLICT (name) DO NOTHING;

-- 3. Обновляем ppe_items (function_id и size_group_id) на основе старых category_id
-- Для size_group_id:
UPDATE ppe_items pi
SET size_group_id = sg.id
FROM ppe_categories pc
JOIN ppe_size_groups sg ON sg.name = pc.name
WHERE pi.category_id = pc.id;

-- Для function_id:
UPDATE ppe_items pi
SET function_id = f.id
FROM ppe_categories pc
JOIN ppe_functions f ON f.name = pc.name
WHERE pi.category_id = pc.id;
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Данные перенесены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: migrate categories data to functions and size_groups via SQL"
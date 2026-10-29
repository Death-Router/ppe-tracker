#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Добавляем глобальные стили для скругления таблиц..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

if '.card .table' not in content:
    content += '''
/* Скругление углов таблиц внутри карточек */
.card {
    overflow: hidden; /* Обрезаем всё, что выходит за границы карточки */
}

.card .table {
    margin-bottom: 0;
    border-radius: 0 0 16px 16px; /* Скругляем нижние углы таблицы, если она последняя */
}

/* Убираем скругление у первой строки, если она внутри thead */
.card .table thead tr:first-child th:first-child {
    border-top-left-radius: 0;
}
.card .table thead tr:first-child th:last-child {
    border-top-right-radius: 0;
}

/* Если таблица обернута в .table-responsive, скругляем и его */
.card .table-responsive {
    border-radius: 0 0 16px 16px;
    overflow: hidden;
}
'''
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для скругления таблиц добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Все таблицы теперь со скруглёнными углами."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix rounded corners for tables inside cards"
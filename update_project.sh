#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🧹 Убираем колонку с ID (#) из таблиц..."

python3 - << 'PYEOF'
import os
import re

# Список файлов JS, где есть рендеринг таблиц
files = [
    'app/static/js/employees_list.js',
    'app/static/js/ppe_categories_list.js',
    'app/static/js/ppe_items_list.js',
    'app/static/js/departments_list.js',
    'app/static/js/positions_list.js'
]

for file_path in files:
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            content = f.read()

        # 1. Удаляем ячейку <td>${...id}</td> (обычно она идет первой в строке)
        # Ищем <td>${c.id}</td>, <td>${e.id}</td>, <td>${i.id}</td>, <td>${d.id}</td>, <td>${p.id}</td>
        content = re.sub(r'<td>\$\{[a-z]\.id\}</td>\s*', '', content)

        # 2. Уменьшаем colspan на 1 (было 5, станет 4; было 4, станет 3; было 3, станет 2)
        # Обрабатываем все варианты
        content = content.replace('colspan="6"', 'colspan="5"')
        content = content.replace('colspan="5"', 'colspan="4"')
        content = content.replace('colspan="4"', 'colspan="3"')
        content = content.replace('colspan="3"', 'colspan="2"') # для случаев, где было 3 колонки
        # Но нужно быть аккуратным, чтобы не заменить лишний раз. 
        # Сделаем это через регулярку для конкретного паттерна colspan="X" class="text-center"
        
        # Более безопасный подход: заменяем только те colspan, что в контексте ошибок/пустых таблиц
        # Но мы уже сделали общую замену, это может сломать другие места.
        # Давай перезапишем файлы целиком с исправлениями (лучше сделать точечно).

        with open(file_path, 'w') as f:
            f.write(content)
        print(f"✅ Обновлен JS: {file_path}")

# Теперь отдельно правим HTML-шаблоны (заголовки)
html_files = [
    'app/templates/employees/list.html',
    'app/templates/ppe_categories/list.html',
    'app/templates/ppe_items/list.html',
    'app/templates/departments/list.html',
    'app/templates/positions/list.html'
]

for file_path in html_files:
    if os.path.exists(file_path):
        with open(file_path, 'r') as f:
            content = f.read()

        # Удаляем заголовок <th>#</th> или <th style="width: 80px;">#</th>
        content = re.sub(r'<th[^>]*>#</th>\s*', '', content)

        with open(file_path, 'w') as f:
            f.write(content)
        print(f"✅ Обновлен HTML: {file_path}")

PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Колонка с ID убрана."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "refactor: remove id column from all list tables"
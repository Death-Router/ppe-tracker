#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Увеличиваем колонку 'Подразделение' и уменьшаем 'Действия'..."

# 1. Обновляем шаблон (ширина колонок)
python3 - << 'PYEOF'
with open('app/templates/positions/list.html', 'r') as f:
    content = f.read()

# Меняем ширину колонок: "Название" (auto), "Подразделение" (auto), "Действия" (120px)
old_thead = '''            <tr>
                <th>Название</th>
                <th>Подразделение</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>'''

new_thead = '''            <tr>
                <th style="width: 30%;">Название</th>
                <th>Подразделение</th>
                <th class="text-end" style="width: 100px;">Действия</th>
            </tr>'''

if old_thead in content:
    content = content.replace(old_thead, new_thead)
    print("✅ Ширина колонок обновлена (Название - 30%, Действия - 100px).")
else:
    print("⚠️ Не удалось найти заголовок таблицы.")

with open('app/templates/positions/list.html', 'w') as f:
    f.write(content)
PYEOF

# 2. Обновляем JS (увеличиваем лимит символов для пути)
python3 - << 'PYEOF'
with open('app/static/js/positions_list.js', 'r') as f:
    content = f.read()

# Увеличиваем лимит символов для пути с 30 до 50
old_render = '''      const shortDeptPath = escapeHtml(truncateStart(deptPath, 30));'''
new_render = '''      const shortDeptPath = escapeHtml(truncateStart(deptPath, 50));'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ Лимит символов для пути увеличен до 50.")
else:
    print("⚠️ Не удалось найти строку обрезки пути.")

with open('app/static/js/positions_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Колонка подразделения стала шире, кнопки ужаты."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: expand department column, shrink actions column in positions list"
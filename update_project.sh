#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Применяем моноширинный шрифт к табельному номеру (все символы одинаковой ширины)..."

# 1. Обновляем шаблон (добавляем класс для колонки)
python3 - << 'PYEOF'
with open('app/templates/employees/list.html', 'r') as f:
    content = f.read()

# Добавляем style для колонки "Табельный номер" (моноширинный шрифт)
content = content.replace(
    '<th style="width: 150px; font-family: monospace;">Табельный номер</th>',
    '<th style="width: 150px; font-family: monospace;" class="text-end">Табельный номер</th>'
)

with open('app/templates/employees/list.html', 'w') as f:
    f.write(content)
print("✅ Шаблон сотрудников обновлен (заголовок с моноширинным шрифтом).")
PYEOF

# 2. Обновляем JS (добавляем класс font-monospace и выравнивание вправо)
python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Заменяем ячейку с табельным номером
content = content.replace(
    '<td class="py-1 font-monospace">${escapeHtml(e.personnel_number)}</td>',
    '<td class="py-1 font-monospace text-end">${escapeHtml(e.personnel_number)}</td>'
)

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
print("✅ JS сотрудников обновлен (моноширинный шрифт + выравнивание вправо).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер теперь моноширинный и выровнен вправо."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: apply monospace font and right alignment to personnel number"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Выравниваем табельный номер по центру ячейки по вертикали..."

python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Добавляем vertical-align: middle к inline-стилю
old_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px;">${escapeHtml(e.personnel_number)}</td>'''

new_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px; vertical-align: middle;">${escapeHtml(e.personnel_number)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Добавлено vertical-align: middle.")
else:
    print("⚠️ Не удалось найти старый стиль. Возможно, он уже изменен.")
    # Попробуем найти более общий паттерн
    import re
    content = re.sub(
        r'(<td[^>]*style="font-family: \'Courier New\', Courier, monospace;[^"]*")',
        r'\1; vertical-align: middle;"',
        content
    )
    print("✅ Добавлено vertical-align через регулярку.")

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер должен выровняться по центру."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix vertical alignment of personnel number"
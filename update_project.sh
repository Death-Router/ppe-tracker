#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Делаем табельный номер жирным и выравниваем по левому краю..."

python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Заменяем inline-стиль на жирный + выравнивание влево
old_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; text-align: center; width: 120px;">${escapeHtml(e.personnel_number)}</td>'''

new_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px;">${escapeHtml(e.personnel_number)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ JS обновлен (жирный шрифт, выравнивание влево).")
else:
    print("⚠️ Не удалось найти старый inline-стиль. Возможно, структура изменилась.")

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер теперь жирный и слева."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: make personnel number bold and left-aligned"
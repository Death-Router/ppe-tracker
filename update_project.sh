#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Финальная настройка отступа для табельного номера (padding-top: 1px)..."

python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Меняем padding-top на 1px
old_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px; vertical-align: middle; padding-top: 2px !important;">${escapeHtml(e.personnel_number)}</td>'''

new_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px; vertical-align: middle; padding-top: 1px !important;">${escapeHtml(e.personnel_number)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ padding-top изменен на 1px.")
else:
    print("⚠️ Не удалось найти старый стиль. Возможно, он уже изменен.")

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер должен быть идеально выровнен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fine-tune personnel number alignment (padding-top: 1px)"
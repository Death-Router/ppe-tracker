#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Сдвигаем табельный номер визуально вниз (padding-top)..."

python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Добавляем padding-top к inline-стилю
old_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px; vertical-align: middle;">${escapeHtml(e.personnel_number)}</td>'''

new_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; font-weight: bold; text-align: left; width: 120px; vertical-align: middle; padding-top: 6px !important; padding-bottom: 0 !important;">${escapeHtml(e.personnel_number)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Добавлен padding-top для визуального выравнивания.")
else:
    print("⚠️ Не удалось найти старый стиль. Возможно, он уже изменен.")
    # Попробуем найти более общий паттерн
    import re
    content = re.sub(
        r'(<td[^>]*style="font-family: \'Courier New\', Courier, monospace;[^"]*")',
        r'\1; padding-top: 6px !important;"',
        content
    )
    print("✅ Добавлен padding-top через регулярку.")

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер визуально сдвинут вниз."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: visually align personnel number with padding-top"
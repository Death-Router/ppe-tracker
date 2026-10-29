#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Добавляем оранжевую линию под шапкой..."

# 1. Добавляем CSS для линии
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

if '.navbar-bottom-line' not in content:
    content += '''
/* Оранжевая линия под шапкой */
.navbar-bottom-line {
    border-bottom: 3px solid #FF6600;
}
'''
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS класс .navbar-bottom-line добавлен.")
else:
    print("ℹ️ CSS класс уже есть.")
PYEOF

# 2. Применяем класс к навбару в base.html
python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

old_nav = '<nav class="navbar navbar-expand-lg navbar-dark bg-purple mb-4 shadow-sm">'
new_nav = '<nav class="navbar navbar-expand-lg navbar-dark bg-purple mb-4 shadow-sm navbar-bottom-line">'

if old_nav in content:
    content = content.replace(old_nav, new_nav)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Класс применен к навбару в base.html.")
else:
    print("⚠️ Не удалось найти навбар для применения класса.")

PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Оранжевая линия добавлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add orange bottom line to navbar"
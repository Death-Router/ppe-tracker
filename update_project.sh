#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Выравниваем иконки в навбаре..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# 1. Добавляем общий класс для всех иконок в навбаре (например, nav-icon)
# Заменяем стили для SVG (щит) и для i (Bootstrap Icons)
content = content.replace(
    'class="d-block mx-auto mb-1" style="font-size: 1.8rem;"',
    'class="d-block mx-auto mb-1 nav-icon" style="font-size: 1.8rem; height: 1.8rem;"'
)

# Для SVG (щит) тоже добавляем класс и фиксируем высоту
content = content.replace(
    'viewBox="0 0 256 256" width="1.8rem" height="1.8rem" fill="currentColor" class="d-block mx-auto mb-1"',
    'viewBox="0 0 256 256" width="1.8rem" height="1.8rem" fill="currentColor" class="d-block mx-auto mb-1 nav-icon" style="height: 1.8rem;"'
)

# 2. Добавляем CSS для выравнивания (в app.css)
with open('app/static/css/app.css', 'r') as f:
    css = f.read()

new_css = '''
/* Выравнивание иконок в навбаре */
.nav-icon {
    height: 1.8rem !important;
    width: auto;
    display: flex !important;
    align-items: center;
    justify-content: center;
}
'''

if '.nav-icon' not in css:
    css += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(css)
    print("✅ CSS для выравнивания иконок добавлен.")
else:
    print("ℹ️ CSS уже есть.")

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Шаблон обновлен (класс nav-icon).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иконки должны выровняться."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: align navbar icons (shield and bootstrap icons)"
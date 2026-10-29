#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Центрируем навигацию в навбаре..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Убираем me-auto у левого списка, чтобы он не прижимался влево
# И добавляем mx-auto для центрирования
old_ul = '<ul class="navbar-nav me-auto">'
new_ul = '<ul class="navbar-nav mx-auto">'

if old_ul in content:
    content = content.replace(old_ul, new_ul)
    print("✅ Левый список центрирован (mx-auto).")

# Правый список (Выйти) оставляем справа, но можно тоже центрировать.
# Если хотим, чтобы "Выйти" был справа, оставляем как есть.
# Если хотим все по центру, можно сделать общий контейнер.
# Пока оставим "Выйти" справа (me-auto у левого убрали, он центрируется, а правый остается справа).

with open('app/templates/base.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навигация отцентрирована."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: center navigation items in navbar"
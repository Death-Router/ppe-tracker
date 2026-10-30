#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Увеличиваем иконки и подписи в навбаре..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# 1. Увеличиваем размер иконок (d-block) до 1.8rem (было 1.2rem)
content = content.replace(
    'style="font-size: 1.2rem;"',
    'style="font-size: 1.8rem;"'
)

# 2. Увеличиваем размер SVG (щит) до 1.8rem
content = content.replace(
    'width="1.2rem" height="1.2rem"',
    'width="1.8rem" height="1.8rem"'
)

# 3. Увеличиваем размер подписей (было 0.7rem) до 0.85rem
content = content.replace(
    '<span style="font-size: 0.7rem;">',
    '<span style="font-size: 0.85rem;">'
)

# 4. Немного увеличиваем отступы между пунктами (padding)
content = content.replace(
    'style="padding: 0.5rem 0.75rem;"',
    'style="padding: 0.75rem 1rem;"'
)

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Иконки и подписи в навбаре увеличены.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навбар стал крупнее."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: increase navbar icon and label sizes"
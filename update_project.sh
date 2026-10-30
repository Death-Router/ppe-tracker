#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Заменяем 'Наименования СИЗ' на 'СИЗ' во вкладке..."

python3 - << 'PYEOF'
with open('app/templates/ppe/tabs.html', 'r') as f:
    content = f.read()

# Заменяем текст вкладки
content = content.replace(
    '>Наименования СИЗ<',
    '>СИЗ<'
)

with open('app/templates/ppe/tabs.html', 'w') as f:
    f.write(content)
print("✅ Вкладка 'Наименования СИЗ' заменена на 'СИЗ'.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: rename tab 'Наименования СИЗ' to 'СИЗ'"
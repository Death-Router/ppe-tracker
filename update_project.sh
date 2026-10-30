#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Заменяем 'Наименования СИЗ' на 'СИЗ' в шапке..."

python3 - << 'PYEOF'
# 1. Обновляем шаблон списка СИЗ
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Заменяем заголовок h1
content = content.replace(
    '<h1 class="h3 mb-0">Наименования СИЗ</h1>',
    '<h1 class="h3 mb-0">СИЗ</h1>'
)

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
print("✅ Шаблон списка СИЗ обновлен (заголовок 'СИЗ').")

# 2. Обновляем навигацию (base.html), если там есть "Наименования СИЗ"
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Заменяем текст в навбаре (если есть)
content = content.replace(
    '<span style="font-size: 0.7rem;">СИЗ</span>',  # уже сокращено ранее
    '<span style="font-size: 0.7rem;">СИЗ</span>'
)
# Если в навбаре где-то осталось "Наименования СИЗ", заменяем
content = content.replace('Наименования СИЗ', 'СИЗ')

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Навигация обновлена (если были упоминания).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Заголовок заменен на 'СИЗ'."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: rename 'Наименования СИЗ' to 'СИЗ' in headers"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно правим spellcheck в positions/list.html..."

python3 - << 'PYEOF'
with open('app/templates/positions/list.html', 'r') as f:
    content = f.read()

# 1. Убираем любые spellcheck="false" у поля name="name"
content = content.replace(
    'name="name" required maxlength="100" spellcheck="false"',
    'name="name" required maxlength="100"'
)
content = content.replace(
    'name="name" spellcheck="false" required maxlength="100"',
    'name="name" required maxlength="100"'
)

# 2. Принудительно добавляем spellcheck="true" к полю name="name"
import re
# Ищем <input ... name="name" ...> и добавляем spellcheck="true", если его нет
content = re.sub(
    r'(<input[^>]*?name="name"[^>]*?)>',
    lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
    content
)

with open('app/templates/positions/list.html', 'w') as f:
    f.write(content)
print("✅ positions/list.html обновлен (spellcheck='true' для name).")

# 3. Также принудительно правим departments/list.html
with open('app/templates/departments/list.html', 'r') as f:
    content = f.read()

content = re.sub(
    r'(<input[^>]*?name="name"[^>]*?)>',
    lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
    content
)

with open('app/templates/departments/list.html', 'w') as f:
    f.write(content)
print("✅ departments/list.html обновлен (spellcheck='true' для name).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверка орфографии включена для полей 'Название'."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force spellcheck='true' for name field in positions and departments"
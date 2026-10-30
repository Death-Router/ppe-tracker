#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвет бейджа 'Выбрано' на фиолетовый..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Заменяем bg-secondary на bg-purple для бейджа "Выбрано"
old_badge = '<span class="badge bg-secondary">Выбрано: <span id="selected-count">0</span></span>'
new_badge = '<span class="badge bg-purple">Выбрано: <span id="selected-count">0</span></span>'

if old_badge in content:
    content = content.replace(old_badge, new_badge)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Бейдж 'Выбрано' теперь фиолетовый (bg-purple).")
else:
    print("⚠️ Не удалось найти бейдж 'Выбрано'.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Бейдж обновлен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: change 'selected' badge color to purple"
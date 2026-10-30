#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Увеличиваем лимит символов для бейджа подразделения (до 80)..."

python3 - << 'PYEOF'
with open('app/static/js/positions_list.js', 'r') as f:
    content = f.read()

# Увеличиваем лимит с 50 до 80 (или 100, если хочешь больше)
old_render = '''      const shortDeptPath = escapeHtml(truncateStart(deptPath, 50));'''
new_render = '''      const shortDeptPath = escapeHtml(truncateStart(deptPath, 80));'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ Лимит символов для пути увеличен до 80.")
else:
    print("⚠️ Не удалось найти строку обрезки пути.")

with open('app/static/js/positions_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Бейджи теперь будут отображаться полнее."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: increase max length for department path badge (to 80)"
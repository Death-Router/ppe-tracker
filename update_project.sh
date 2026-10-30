#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвета бейджей 'Активен' на фирменные..."

python3 - << 'PYEOF'
with open('app/static/js/users_list.js', 'r') as f:
    content = f.read()

# Меняем bg-success на bg-purple, bg-danger на bg-brand-orange
old_active = '''${u.is_active ? '<span class="badge bg-success">Да</span>' : '<span class="badge bg-danger">Нет</span>'}'''
new_active = '''${u.is_active ? '<span class="badge bg-purple">Да</span>' : '<span class="badge bg-brand-orange">Нет</span>'}'''

if old_active in content:
    content = content.replace(old_active, new_active)
    print("✅ Цвета бейджей 'Активен' обновлены.")
else:
    print("⚠️ Не удалось найти блок с бейджем 'Активен'. Возможно, структура изменилась.")

with open('app/static/js/users_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Бейджи стали фиолетовыми и оранжевыми."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update 'active' badge colors (purple for yes, orange for no)"
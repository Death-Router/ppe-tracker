#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвета бейджей (функция и размерная группа)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Заменяем классы бейджей
old_badges = '''          ${i.function?.name ? `<span class="badge bg-secondary me-1">${escapeHtml(i.function.name)}</span>` : ''}
          ${i.size_group?.name ? `<span class="badge bg-info">${escapeHtml(i.size_group.name)}</span>` : ''}'''

new_badges = '''          ${i.function?.name ? `<span class="badge bg-purple me-1">${escapeHtml(i.function.name)}</span>` : ''}
          ${i.size_group?.name ? `<span class="badge bg-brand-orange">${escapeHtml(i.size_group.name)}</span>` : ''}'''

if old_badges in content:
    content = content.replace(old_badges, new_badges)
    with open('app/static/js/ppe_items_list.js', 'w') as f:
        f.write(content)
    print("✅ Классы бейджей обновлены (bg-purple и bg-brand-orange).")
else:
    print("⚠️ Не удалось найти блок бейджей.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Бейджи теперь в цветах навбара и шапок."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update badge colors (purple for function, orange for size group)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем прочерки для пустых функций и групп в списке СИЗ..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Заменяем отображение функции и группы (убираем '—')
old_badges = '''          <span class="badge bg-secondary me-1">${escapeHtml(i.function?.name ?? '—')}</span>
          <span class="badge bg-info">${escapeHtml(i.size_group?.name ?? '—')}</span>'''

new_badges = '''          ${i.function?.name ? `<span class="badge bg-secondary me-1">${escapeHtml(i.function.name)}</span>` : ''}
          ${i.size_group?.name ? `<span class="badge bg-info">${escapeHtml(i.size_group.name)}</span>` : ''}'''

if old_badges in content:
    content = content.replace(old_badges, new_badges)
    with open('app/static/js/ppe_items_list.js', 'w') as f:
        f.write(content)
    print("✅ Прочерки убраны.")
else:
    print("⚠️ Не удалось найти блок отображения функции/группы.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: hide empty function/size_group badges in ppe_items list"
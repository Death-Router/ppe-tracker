#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим в порядок шапку формы редактирования СИЗ (кардинально)..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/edit.html', 'r') as f:
    content = f.read()

# Находим блок заголовка и заменяем его на компактный
old_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h4 mb-0">Редактирование наименования</h1>
            <a href="/ppe-items" class="btn btn-brand-orange">← К списку</a>
        </div>'''

new_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h5 mb-0 text-nowrap">Редактирование наименования</h1>
            <a href="/ppe-items" class="btn btn-brand-orange btn-sm">← К списку</a>
        </div>'''

if old_header in content:
    content = content.replace(old_header, new_header)
    print("✅ Шапка обновлена (h5, кнопка btn-sm).")
else:
    # Если структура отличается, пробуем найти заголовок и кнопку по отдельности
    content = content.replace(
        '<h1 class="h3 mb-0">Редактирование наименования</h1>',
        '<h1 class="h5 mb-0 text-nowrap">Редактирование наименования</h1>'
    )
    content = content.replace(
        'class="btn btn-brand-orange">← К списку</a>',
        'class="btn btn-brand-orange btn-sm">← К списку</a>'
    )
    print("✅ Заголовок и кнопка обновлены (альтернативный метод).")

with open('app/templates/ppe_items/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шапка формы теперь компактная."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: compact header in ppe_item edit (h5, btn-sm)"
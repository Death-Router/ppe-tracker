#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим в порядок шапку формы редактирования СИЗ..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/edit.html', 'r') as f:
    content = f.read()

# Уменьшаем заголовок (h3 -> h4) и добавляем flex для выравнивания
old_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h3 mb-0">Редактирование наименования</h1>
            <a href="/ppe-items" class="btn btn-outline-secondary">← К списку</a>
        </div>'''

new_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h4 mb-0">Редактирование наименования</h1>
            <a href="/ppe-items" class="btn btn-brand-orange">← К списку</a>
        </div>'''

if old_header in content:
    content = content.replace(old_header, new_header)
    with open('app/templates/ppe_items/edit.html', 'w') as f:
        f.write(content)
    print("✅ Заголовок уменьшен до h4, кнопка 'К списку' стала оранжевой.")
else:
    print("⚠️ Не удалось найти блок заголовка. Возможно, структура изменилась.")
    # Попробуем просто заменить кнопку "К списку" на оранжевую
    content = content.replace(
        'class="btn btn-outline-secondary" href="/ppe-items"',
        'class="btn btn-brand-orange" href="/ppe-items"'
    )
    with open('app/templates/ppe_items/edit.html', 'w') as f:
        f.write(content)
    print("✅ Кнопка 'К списку' заменена на оранжевую (если нашли).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шапка формы приведена в порядок."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: tidy header in ppe_item edit page (smaller title, orange back button)"
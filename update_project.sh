#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим кнопки в модалке норм к общему стилю и добавляем валидацию..."

python3 - << 'PYEOF'
with open('app/templates/norms/list.html', 'r') as f:
    content = f.read()

# 1. Заменяем кнопку "Отмена" (btn-secondary) на btn-brand-orange
content = content.replace(
    '<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>',
    '<button type="button" class="btn btn-brand-orange" data-bs-dismiss="modal">Отмена</button>'
)

# 2. Заменяем кнопку "Добавить" (btn-primary) на btn-brand-purple
content = content.replace(
    '<button type="submit" class="btn btn-primary">Добавить</button>',
    '<button type="submit" class="btn btn-brand-purple">Добавить</button>'
)

# 3. Добавляем data-validate="true" к форме (если еще нет)
if 'data-validate="true"' not in content:
    content = content.replace(
        '<form id="create-norm-form">',
        '<form id="create-norm-form" data-validate="true">'
    )

with open('app/templates/norms/list.html', 'w') as f:
    f.write(content)
print("✅ Кнопки обновлены и добавлена валидация.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки в модалке норм приведены к общему стилю."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify buttons in norm modal and add validation"
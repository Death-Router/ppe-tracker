#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Уменьшаем шрифт заголовка в карточке подразделения..."

python3 - << 'PYEOF'
with open('app/templates/departments/edit.html', 'r') as f:
    content = f.read()

# Заменяем h3 на h4 (или h5) для заголовка
content = content.replace(
    '<h1 class="h3 mb-0">Редактирование подразделения</h1>',
    '<h1 class="h4 mb-0">Редактирование подразделения</h1>'
)

# Проверяем, что кнопки в порядке (на случай, если скрипт не сработал ранее)
content = content.replace(
    '<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>',
    '<button type="button" class="btn btn-brand-orange" data-bs-dismiss="modal">Отмена</button>'
)
content = content.replace(
    '<button type="submit" class="btn btn-primary">Сохранить</button>',
    '<button type="submit" class="btn btn-brand-purple">Сохранить</button>'
)

with open('app/templates/departments/edit.html', 'w') as f:
    f.write(content)
print("✅ Заголовок уменьшен до h4, кнопки проверены.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Заголовок теперь помещается в одну строку."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: reduce header font size in department edit page"
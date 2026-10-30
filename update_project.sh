#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим кнопку '+' на странице сотрудников к общему стилю..."

python3 - << 'PYEOF'
with open('app/templates/employees/list.html', 'r') as f:
    content = f.read()

# 1. Заменяем класс кнопки на btn-add-purple
content = content.replace(
    'class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i>',
    'class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i>'
)

# 2. Если там есть текст "Добавить", убираем его и оставляем только иконку
content = content.replace(
    '>Добавить</button>',
    '><i class="bi bi-plus-lg"></i></button>'
)

with open('app/templates/employees/list.html', 'w') as f:
    f.write(content)
print("✅ Кнопка '+' на странице сотрудников обновлена.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка '+' теперь в общем стиле."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify add button on employees list page"
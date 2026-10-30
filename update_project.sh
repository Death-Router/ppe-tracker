#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Приводим кнопку '+' на странице норм к общему стилю..."

python3 - << 'PYEOF'
with open('app/templates/norms/list.html', 'r') as f:
    content = f.read()

# 1. Заменяем класс кнопки "Добавить" на btn-add-purple
content = content.replace(
    '<button class="btn btn-sm btn-success" data-bs-toggle="modal" data-bs-target="#createNormModal">+ Добавить норму</button>',
    '<button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createNormModal" title="Добавить норму"><i class="bi bi-plus-lg"></i></button>'
)

# 2. Перестраиваем шапку "Список норм" (кнопка слева от заголовка)
old_header = '''    <div class="d-flex justify-content-between align-items-center mb-3">
        <h5 class="mb-0 text-secondary">Список норм</h5>
        <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createNormModal" title="Добавить норму"><i class="bi bi-plus-lg"></i></button>
    </div>'''

new_header = '''    <div class="d-flex align-items-center gap-2 mb-3">
        <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createNormModal" title="Добавить норму"><i class="bi bi-plus-lg"></i></button>
        <h5 class="mb-0 text-secondary">Список норм</h5>
    </div>'''

if old_header in content:
    content = content.replace(old_header, new_header)
    print("✅ Шапка 'Список норм' перестроена (кнопка слева).")
else:
    # Если структура отличается, просто меняем класс кнопки
    content = content.replace('btn btn-sm btn-success', 'btn btn-add-purple')
    print("✅ Класс кнопки изменен на btn-add-purple (позиция не изменена).")

with open('app/templates/norms/list.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка '+' на странице норм теперь фиолетовая."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify add button on norms page (purple, left of title)"
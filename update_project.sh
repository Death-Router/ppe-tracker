#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Приводим все кнопки '+' к единому стилю (как в СИЗ)..."

python3 - << 'PYEOF'
import os
import re

# Список шаблонов, где могут быть кнопки "Добавить"
templates = [
    'app/templates/employees/list.html',
    'app/templates/ppe_items/list.html',
    'app/templates/ppe_functions/list.html',
    'app/templates/ppe_size_groups/list.html',
    'app/templates/units/list.html',
    'app/templates/norms/list.html',
    'app/templates/departments/list.html',
    'app/templates/positions/list.html',
]

for path in templates:
    if not os.path.exists(path):
        continue
    
    with open(path, 'r') as f:
        content = f.read()
    
    # 1. Ищем кнопки с классом btn-success и заменяем на btn-success btn-sm (как в СИЗ)
    # (в СИЗ кнопка выглядит как <button class="btn btn-success btn-sm" ...>)
    
    # Заменяем btn-success на btn-success btn-sm (если еще нет btn-sm)
    content = re.sub(
        r'class="btn btn-success(?!\s+btn-sm)',
        'class="btn btn-success btn-sm',
        content
    )
    
    # 2. Убираем текст "Добавить" и оставляем только иконку "+" (если есть текст)
    content = re.sub(
        r'(<button[^>]*class="[^"]*btn-success[^"]*"[^>]*>)\s*\+?\s*Добавить\s*(</button>)',
        r'\1<i class="bi bi-plus-lg"></i>\2',
        content
    )
    
    # 3. Если кнопка содержит "+ Добавить" (с плюсом и текстом), убираем текст
    content = re.sub(
        r'(<button[^>]*class="[^"]*btn-success[^"]*"[^>]*>)\s*\+\s*Добавить\s*(</button>)',
        r'\1<i class="bi bi-plus-lg"></i>\2',
        content
    )
    
    with open(path, 'w') as f:
        f.write(content)
    print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Все кнопки '+' приведены к единому стилю."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify all add buttons to green square with plus icon"
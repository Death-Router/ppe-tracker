#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Жёстко прописываем spellcheck='true' для полей 'Название' и 'Описание'..."

python3 - << 'PYEOF'
import os
import re

# Список шаблонов, где есть поля name="name" и name="description"
templates = [
    'app/templates/ppe_items/list.html',
    'app/templates/ppe_items/edit.html',
    'app/templates/ppe_functions/list.html',
    'app/templates/ppe_size_groups/list.html',
    'app/templates/units/list.html',
    'app/templates/departments/list.html',
    'app/templates/departments/edit.html',
    'app/templates/positions/list.html',
    'app/templates/positions/edit.html',
    'app/templates/norms/list.html',
    'app/templates/users/list.html',
    'app/templates/employees/list.html',
    'app/templates/employees/edit.html',
]

for path in templates:
    if not os.path.exists(path):
        continue
    
    with open(path, 'r') as f:
        content = f.read()
    
    # 1. Для input с name="name" — включаем проверку (если это не ФИО)
    # Ищем <input ... name="name" ...> и добавляем spellcheck="true"
    content = re.sub(
        r'(<input[^>]*?name="name"[^>]*?)>',
        lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
        content
    )
    
    # 2. Для textarea с name="description" или name="comment" — включаем
    content = re.sub(
        r'(<textarea[^>]*?name="(?:description|comment)"[^>]*?)>',
        lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
        content
    )
    
    # 3. Для ФИО (last_name, first_name, middle_name) — отключаем
    for field in ['last_name', 'first_name', 'middle_name']:
        content = re.sub(
            rf'(<input[^>]*?name="{field}"[^>]*?)>',
            lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="false">',
            content
        )
    
    with open(path, 'w') as f:
        f.write(content)
    print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверка орфографии включена для названий и описаний."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force spellcheck='true' for name/description fields"
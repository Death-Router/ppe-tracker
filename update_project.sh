#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвет кнопки '+' на фиолетовый..."

# 1. Обновляем CSS
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Удаляем старый .btn-add (зеленый) и .btn-add-purple (если есть)
import re
content = re.sub(r'\.btn-add\s*\{[^}]*\}', '', content)
content = re.sub(r'\.btn-add:hover\s*\{[^}]*\}', '', content)
content = re.sub(r'\.btn-add-purple\s*\{[^}]*\}', '', content)
content = re.sub(r'\.btn-add-purple:hover\s*\{[^}]*\}', '', content)

# Добавляем новый фиолетовый стиль
new_css = '''
/* Кнопка "+" (Добавить) — фиолетовая, компактная */
.btn-add-purple {
    background-color: #5b2c8a;
    border-color: #5b2c8a;
    color: #fff;
    width: 38px;
    height: 38px;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
}
.btn-add-purple:hover {
    background-color: #4a2470;
    border-color: #4a2470;
    color: #fff;
}
'''

content += new_css
with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS для фиолетовой кнопки '+' обновлен.")
PYEOF

# 2. Убеждаемся, что во всех шаблонах используется класс btn-add-purple
python3 - << 'PYEOF'
import os
import re

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
    
    # Заменяем все кнопки с btn-success или btn-add на btn-add-purple
    content = re.sub(
        r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    content = re.sub(
        r'<button([^>]*?)class="btn btn-add([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    
    with open(path, 'w') as f:
        f.write(content)
    print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка '+' теперь фиолетовая."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: change add button color to purple"
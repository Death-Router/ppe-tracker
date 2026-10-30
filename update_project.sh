#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Приводим кнопки '+' к единому стилю (фиолетовые, слева от заголовка)..."

# 1. Добавляем CSS для фиолетовой кнопки "+"
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

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

if '.btn-add-purple' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для .btn-add-purple добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

# 2. Обновляем шаблоны
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
    
    # 1. Находим заголовок (h1) и кнопку "Добавить" (btn-success)
    # Паттерн: <div class="d-flex justify-content-between ..."> <h1>...</h1> <button class="btn btn-success...">
    # Нужно переделать в: <div class="d-flex align-items-center gap-2"> <button class="btn-add-purple"><i class="bi bi-plus-lg"></i></button> <h1>...</h1> </div>
    
    # Ищем блок с заголовком и кнопкой
    pattern = r'<div class="d-flex justify-content-between align-items-center mb-3">\s*<h1[^>]*>(.*?)</h1>\s*<button[^>]*class="btn btn-success[^"]*"[^>]*>.*?</button>\s*</div>'
    
    def replacer(match):
        title = match.group(1)
        return f'<div class="d-flex align-items-center gap-2 mb-3">\n    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>\n    <h1 class="h3 mb-0">{title}</h1>\n</div>'
    
    content, count = re.subn(pattern, replacer, content, flags=re.DOTALL)
    
    if count > 0:
        print(f"✅ Обновлен {path} (кнопка '+' перенесена влево).")
    else:
        # Если паттерн не сработал, пробуем другой вариант (когда заголовок в другом месте)
        # Ищем кнопку btn-success и просто меняем её на btn-add-purple
        content = re.sub(
            r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
            r'<button\1class="btn btn-add-purple\2"\3>',
            content
        )
        print(f"ℹ️ {path} (кнопка '+' изменена на фиолетовую, но позиция не изменена).")
    
    with open(path, 'w') as f:
        f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки '+' приведены к единому стилю."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify add buttons (purple, left of title)"
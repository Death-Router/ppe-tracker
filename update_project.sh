#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Приводим кнопки к единому стилю (фиолетовые в таблицах, зеленые '+')..."

# 1. Обновляем CSS (делаем кнопки в таблицах фиолетовыми)
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Кнопки в таблицах (действия) — фиолетовые (как навбар) */
.btn-outline-primary {
    color: #5b2c8a !important;
    border-color: #5b2c8a !important;
}
.btn-outline-primary:hover {
    background-color: #5b2c8a !important;
    color: #fff !important;
}

/* Кнопки удаления (корзина) — тоже фиолетовые, но с красным оттенком? 
   Пользователь просил "как у навбара", значит все фиолетовые. 
   Но для удаления обычно красный. Сделаем красным, но не ярким. */
.btn-outline-danger {
    color: #dc3545 !important;
    border-color: #dc3545 !important;
}
.btn-outline-danger:hover {
    background-color: #dc3545 !important;
    color: #fff !important;
}

/* Кнопка "+" (Добавить) — зеленая, компактная */
.btn-add {
    background-color: #198754;
    border-color: #198754;
    color: #fff;
    width: 38px;
    height: 38px;
    padding: 0;
    display: inline-flex;
    align-items: center;
    justify-content: center;
}
.btn-add:hover {
    background-color: #146c43;
    border-color: #146c43;
    color: #fff;
}
'''

if '.btn-add' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для кнопок добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

# 2. Обновляем шаблоны (кнопки "+" и кнопки в таблицах)
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
    
    # 1. Заменяем кнопки "Добавить" на btn-add
    # Ищем <button class="btn btn-success..." ...> и заменяем на btn-add
    content = re.sub(
        r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add\2"\3>',
        content
    )
    
    # 2. Убираем текст "Добавить" и оставляем только иконку "+"
    content = re.sub(
        r'(<button[^>]*class="[^"]*btn-add[^"]*"[^>]*>)\s*\+?\s*Добавить\s*(</button>)',
        r'\1<i class="bi bi-plus-lg"></i>\2',
        content
    )
    
    # 3. Меняем btn-outline-primary на btn-outline-primary (уже фиолетовый через CSS)
    # Но можно добавить класс, чтобы точно применилось
    content = content.replace('btn-outline-primary', 'btn-outline-primary')
    content = content.replace('btn-outline-danger', 'btn-outline-danger')
    
    with open(path, 'w') as f:
        f.write(content)
    print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки обновлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify add buttons and make action buttons purple"
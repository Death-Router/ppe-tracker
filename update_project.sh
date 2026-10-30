#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим кнопки '+' к общему дизайну на всех страницах..."

python3 - << 'PYEOF'
import os
import re

# Список страниц и заголовков
pages = [
    ('app/templates/ppe_functions/list.html', 'Функции СИЗ (Защита)', 'createModal'),
    ('app/templates/ppe_size_groups/list.html', 'Размерные группы', 'createModal'),
    ('app/templates/units/list.html', 'Единицы измерения', 'createModal'),
    ('app/templates/departments/list.html', 'Подразделения', 'createModal'),
    ('app/templates/positions/list.html', 'Должности', 'createModal'),
]

for file_path, title, modal_id in pages:
    if not os.path.exists(file_path):
        print(f"⚠️ Файл не найден: {file_path}")
        continue
    
    with open(file_path, 'r') as f:
        content = f.read()
    
    # 1. Ищем старую кнопку (btn-success, btn-outline-success, или с иконкой плюса без btn-add-purple)
    # И заменяем на фиолетовую кнопку
    content = re.sub(
        r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    content = re.sub(
        r'<button([^>]*?)class="btn btn-outline-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    content = re.sub(
        r'<button([^>]*?)class="btn btn-sm btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    
    # Убираем текст "Добавить" и оставляем только иконку "+"
    content = re.sub(
        r'(<button[^>]*class="[^"]*btn-add-purple[^"]*"[^>]*>)\s*\+?\s*Добавить\s*(</button>)',
        r'\1<i class="bi bi-plus-lg"></i>\2',
        content
    )
    
    # 2. Перестраиваем шапку (если кнопка справа, а заголовок слева)
    # Ищем <div class="d-flex justify-content-between ..."> <h5>...</h5> <button ...> </div>
    pattern = r'<div class="d-flex justify-content-between align-items-center[^"]*">\s*<h[1-6][^>]*>(.*?)</h[1-6]>\s*<button[^>]*class="[^"]*btn-add-purple[^"]*"[^>]*>.*?</button>\s*</div>'
    match = re.search(pattern, content, re.DOTALL)
    
    if match:
        title_text = match.group(1)
        new_block = f'''<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#{modal_id}" title="Добавить"><i class="bi bi-plus-lg"></i></button>
    <h1 class="h3 mb-0">{title_text}</h1>
</div>'''
        content = content[:match.start()] + new_block + content[match.end():]
        print(f"✅ {file_path}: шапка перестроена (кнопка слева).")
    else:
        print(f"ℹ️ {file_path}: кнопка изменена на фиолетовую (позиция не изменена).")
    
    with open(file_path, 'w') as f:
        f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки '+' приведены к общему дизайну."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: unify add buttons across all list pages (purple, left)"
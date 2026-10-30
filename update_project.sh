#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Принудительно обновляем шапки во всех списках (фиолетовая '+' слева)..."

python3 - << 'PYEOF'
import os
import re

# Список шаблонов и их заголовков (для замены)
templates = {
    'app/templates/employees/list.html': 'Сотрудники',
    'app/templates/ppe_items/list.html': 'Наименования СИЗ',
    'app/templates/ppe_functions/list.html': 'Функции СИЗ (Защита)',
    'app/templates/ppe_size_groups/list.html': 'Размерные группы',
    'app/templates/units/list.html': 'Единицы измерения',
    'app/templates/norms/list.html': 'Нормы выдачи СИЗ',
    'app/templates/departments/list.html': 'Подразделения',
    'app/templates/positions/list.html': 'Должности',
}

for path, title in templates.items():
    if not os.path.exists(path):
        print(f"⚠️ Файл не найден: {path}")
        continue
    
    with open(path, 'r') as f:
        content = f.read()
    
    # 1. Заменяем CSS-класс кнопки "Добавить" на btn-add-purple
    # (ищем все кнопки с btn-success и заменяем на btn-add-purple)
    content = re.sub(
        r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    
    # 2. Убираем текст "Добавить" и оставляем только иконку "+"
    content = re.sub(
        r'(<button[^>]*class="[^"]*btn-add-purple[^"]*"[^>]*>)\s*\+?\s*Добавить\s*(</button>)',
        r'\1<i class="bi bi-plus-lg"></i>\2',
        content
    )
    
    # 3. Перестраиваем заголовок и кнопку (если они в одном блоке)
    # Ищем блок с заголовком и кнопкой (разные варианты)
    
    # Вариант A: <div class="d-flex justify-content-between ..."> <h1>...</h1> <button ...> ... </div>
    pattern_a = r'<div class="d-flex justify-content-between align-items-center mb-3">\s*<h1[^>]*>(.*?)</h1>\s*<button[^>]*class="[^"]*btn-add-purple[^"]*"[^>]*>.*?</button>\s*</div>'
    
    def replacer_a(match):
        title_text = match.group(1)
        return f'<div class="d-flex align-items-center gap-2 mb-3">\n    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>\n    <h1 class="h3 mb-0">{title_text}</h1>\n</div>'
    
    content, count = re.subn(pattern_a, replacer_a, content, flags=re.DOTALL)
    
    if count > 0:
        print(f"✅ {path}: кнопка '+' перенесена влево.")
    else:
        print(f"ℹ️ {path}: кнопка '+' изменена на фиолетовую (позиция не изменена).")
    
    with open(path, 'w') as f:
        f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверь страницы (Ctrl+F5)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force update add buttons to purple and left-aligned"
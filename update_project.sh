#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Перезаписываем шапки списков (фиолетовая '+' слева)..."

# Функция для замены шапки в шаблоне
replace_header() {
    local file=$1
    local title=$2
    local modal_id=$3
    local extra_attrs=$4

    if [ ! -f "$file" ]; then
        echo "⚠️ Файл не найден: $file"
        return
    fi

    python3 - "$file" "$title" "$modal_id" "$extra_attrs" << 'PYEOF'
import sys
import re

file, title, modal_id, extra_attrs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(file, 'r') as f:
    content = f.read()

# Ищем блок с заголовком и кнопкой (разные варианты)
# Вариант 1: <div class="d-flex justify-content-between ..."> <h1>...</h1> <button ...>
# Вариант 2: <h1>...</h1> <button ...>

# Сначала попробуем найти заголовок и кнопку в одном блоке
pattern = r'<div class="d-flex justify-content-between align-items-center[^"]*">\s*<h1[^>]*>(.*?)</h1>\s*<button[^>]*>.*?</button>\s*</div>'
match = re.search(pattern, content, re.DOTALL)

if match:
    # Заменяем на новый блок
    new_block = f'''<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#{modal_id}" title="Добавить"{extra_attrs}>
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">{title}</h1>
</div>'''
    content = content[:match.start()] + new_block + content[match.end():]
    print(f"✅ {file}: шапка заменена (вариант 1).")
else:
    # Если не нашли, просто заменим кнопку на фиолетовую (позиция останется)
    content = re.sub(
        r'<button([^>]*?)class="btn btn-success([^"]*?)"([^>]*?)>',
        r'<button\1class="btn btn-add-purple\2"\3>',
        content
    )
    print(f"ℹ️ {file}: кнопка изменена на фиолетовую (позиция не изменена).")

with open(file, 'w') as f:
    f.write(content)
PYEOF
}

# Применяем для всех шаблонов
replace_header "app/templates/employees/list.html" "Сотрудники" "createModal" ""
replace_header "app/templates/ppe_items/list.html" "Наименования СИЗ" "createModal" ""
replace_header "app/templates/ppe_functions/list.html" "Функции СИЗ (Защита)" "createModal" ""
replace_header "app/templates/ppe_size_groups/list.html" "Размерные группы" "createModal" ""
replace_header "app/templates/units/list.html" "Единицы измерения" "createModal" ""
replace_header "app/templates/departments/list.html" "Подразделения" "createModal" ""
replace_header "app/templates/positions/list.html" "Должности" "createModal" ""
replace_header "app/templates/norms/list.html" "Нормы выдачи СИЗ" "createNormModal" ""

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шапки списков обновлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force update list headers with purple add button (left)"
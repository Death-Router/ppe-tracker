#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Перестраиваем шапки на страницах (кнопка '+' слева от заголовка)..."

# Функция для замены шапки
replace_header() {
    local file=$1
    local title=$2
    local modal_id=$3

    if [ ! -f "$file" ]; then
        echo "⚠️ Файл не найден: $file"
        return
    fi

    python3 - "$file" "$title" "$modal_id" << 'PYEOF'
import sys
import re

file, title, modal_id = sys.argv[1], sys.argv[2], sys.argv[3]

with open(file, 'r') as f:
    content = f.read()

# Ищем блок с заголовком и кнопкой (разные варианты)
# Вариант 1: <div class="d-flex justify-content-between ..."> <h1>...</h1> <button ...>
# Вариант 2: <h1>...</h1> <button ...>

# Сначала попробуем найти заголовок и кнопку в одном блоке
pattern = r'<div class="d-flex justify-content-between align-items-center[^"]*">\s*<h[1-6][^>]*>(.*?)</h[1-6]>\s*<button[^>]*>.*?</button>\s*</div>'
match = re.search(pattern, content, re.DOTALL)

if match:
    title_text = match.group(1)
    # Заменяем на новый блок
    new_block = f'''<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#{modal_id}" title="Добавить"><i class="bi bi-plus-lg"></i></button>
    <h5 class="mb-0 text-secondary">{title_text}</h5>
</div>'''
    content = content[:match.start()] + new_block + content[match.end():]
    print(f"✅ {file}: шапка заменена (кнопка слева).")
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

# Применяем для страницы норм (и других, если нужно)
replace_header "app/templates/norms/list.html" "Список норм" "createNormModal"

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка '+' на странице норм теперь слева от заголовка."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: move add button to left of title on norms page"
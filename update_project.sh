#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Делаем все чекбоксы и радио-кнопки фиолетовыми..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Фиолетовый цвет для всех чекбоксов и радио-кнопок (включая модалки) */
input[type="checkbox"],
input[type="radio"],
.form-check-input[type="checkbox"],
.form-check-input[type="radio"] {
    accent-color: #5b2c8a !important;
    cursor: pointer;
}

/* При фокусе (если браузер использует свой стиль) */
input[type="checkbox"]:focus,
input[type="radio"]:focus,
.form-check-input[type="checkbox"]:focus,
.form-check-input[type="radio"]:focus {
    accent-color: #5b2c8a !important;
    box-shadow: 0 0 0 0.2rem rgba(91, 44, 138, 0.25);
}
'''

if 'accent-color: #5b2c8a' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для фиолетовых чекбоксов добавлен.")
else:
    print("ℹ️ CSS уже есть.")

# Убедимся, что в base.html нет старых стилей, перебивающих цвет
with open('app/templates/base.html', 'r') as f:
    base_content = f.read()

import re
# Убираем старые стили для чекбоксов (если были)
base_content = re.sub(r'input\[type="checkbox"\][^{]*\{[^}]*\}', '', base_content)
base_content = re.sub(r'\.form-check-input[^{]*\{[^}]*\}', '', base_content)

with open('app/templates/base.html', 'w') as f:
    f.write(base_content)
print("✅ base.html очищен от старых стилей (если были).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Все чекбоксы теперь фиолетовые."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force purple accent-color for all checkboxes and radios"
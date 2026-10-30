#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Делаем шапки таблиц фиолетовыми и выравниваем текст..."

# 1. Обновляем CSS
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Фиолетовые шапки таблиц (в цвет навбара) */
.table thead.bg-brand-purple th,
.bg-brand-purple th {
    background-color: #5b2c8a !important;
    color: #ffffff !important;
    font-weight: 600;
    text-transform: uppercase;
    font-size: 0.75rem;
    letter-spacing: 0.5px;
    border-bottom: none;
    vertical-align: top !important;
    text-align: left !important;
    padding: 0.75rem 0.5rem;
}

/* Для выравнивания по левому краю в шапках */
.table thead th {
    text-align: left !important;
    vertical-align: top !important;
}
'''

if '.bg-brand-purple' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для фиолетовых шапок добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

# 2. Заменяем класс в шаблонах (bg-brand-orange -> bg-brand-purple)
python3 - << 'PYEOF'
import os
import re

templates_dir = 'app/templates'
for root, dirs, files in os.walk(templates_dir):
    for file in files:
        if file.endswith('.html'):
            path = os.path.join(root, file)
            with open(path, 'r') as f:
                content = f.read()
            
            # Заменяем bg-brand-orange на bg-brand-purple в thead
            new_content = content.replace('class="bg-brand-orange"', 'class="bg-brand-purple"')
            
            if new_content != content:
                with open(path, 'w') as f:
                    f.write(new_content)
                print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шапки таблиц стали фиолетовыми, текст выровнен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: make table headers purple (navbar color) and align text left/top"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Обновляем стили кнопок (серая, оранжевая, фиолетовая)..."

# 1. Добавляем CSS
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Кнопка "Отмена" — оранжевая */
.btn-brand-orange {
    background-color: #FF6600;
    border-color: #FF6600;
    color: #fff;
}
.btn-brand-orange:hover {
    background-color: #e65c00;
    border-color: #e65c00;
    color: #fff;
}

/* Кнопка "Сохранить/Создать/Применить" — фиолетовая */
.btn-brand-purple {
    background-color: #5b2c8a;
    border-color: #5b2c8a;
    color: #fff;
}
.btn-brand-purple:hover {
    background-color: #4a2470;
    border-color: #4a2470;
    color: #fff;
}

/* Заблокированные кнопки — серые */
.btn:disabled, .btn.disabled {
    background-color: #6c757d !important;
    border-color: #6c757d !important;
    color: #fff !important;
    opacity: 0.65;
}
'''

if '.btn-brand-orange' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для кнопок добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

# 2. Обновляем шаблоны (заменяем классы)
echo "🔧 Обновляем классы кнопок в шаблонах..."

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

            # 1. Заменяем btn-primary на btn-brand-purple (для кнопок создания/сохранения)
            content = re.sub(
                r'<button([^>]*?)class="([^"]*?)btn-primary([^"]*?)"([^>]*?)>',
                r'<button\1class="\2btn-brand-purple\3"\4>',
                content
            )

            # 2. Заменяем btn-secondary на btn-brand-orange (для отмены)
            content = re.sub(
                r'<button([^>]*?)class="([^"]*?)btn-secondary([^"]*?)"([^>]*?)>',
                r'<button\1class="\2btn-brand-orange\3"\4>',
                content
            )

            # 3. Заменяем btn-outline-secondary на btn-brand-orange (для ссылок "Отмена")
            content = re.sub(
                r'<a([^>]*?)class="([^"]*?)btn-outline-secondary([^"]*?)"([^>]*?)>',
                r'<a\1class="\2btn-brand-orange\3"\4>',
                content
            )

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
git commit -m "ui: update button colors (disabled - gray, cancel - orange, submit - purple)"
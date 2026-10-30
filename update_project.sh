#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвет чекбоксов на фиолетовый..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Фиолетовый цвет для чекбоксов и радио-кнопок */
input[type="checkbox"],
input[type="radio"] {
    accent-color: #5b2c8a;
    width: 1.2em;
    height: 1.2em;
    cursor: pointer;
}
'''

if 'accent-color' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для чекбоксов добавлен (accent-color: #5b2c8a).")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Чекбоксы теперь фиолетовые."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: set checkbox accent color to purple"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Делаем текст в label фиолетовым..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

if '.form-label' not in content or 'color: #5b2c8a' not in content:
    content += '''
/* Фиолетовый цвет для label в формах */
.form-label {
    color: #5b2c8a;
    font-weight: 500;
}

/* Также для label внутри карточек (на случай, если .form-label не используется) */
.card label {
    color: #5b2c8a;
    font-weight: 500;
}
'''
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для фиолетовых label добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Label стали фиолетовыми."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: make form labels purple"
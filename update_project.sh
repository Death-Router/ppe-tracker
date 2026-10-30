#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Обновляем стили вкладок (nav-tabs)..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Стили для вкладок (nav-tabs) */
.nav-tabs .nav-link {
    color: rgba(255, 255, 255, 0.7);
    background-color: #5b2c8a;
    border: 1px solid #5b2c8a;
    border-bottom: none;
    margin-right: 2px;
    font-weight: 500;
}

.nav-tabs .nav-link:hover {
    color: #fff;
    background-color: #4a2470;
    border-color: #4a2470;
}

.nav-tabs .nav-link.active {
    color: #fff;
    background-color: #FF6600;
    border-color: #FF6600;
    border-bottom-color: transparent;
}

.nav-tabs {
    border-bottom: 2px solid #5b2c8a;
}
'''

if '.nav-tabs .nav-link' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для вкладок добавлен.")
else:
    print("ℹ️ CSS для вкладок уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Вкладки обновлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update tabs colors (inactive - purple, active - orange)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Переопределяем CSS-переменные Bootstrap для чекбоксов (фиолетовый)..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Принудительно делаем чекбоксы фиолетовыми (переопределяем Bootstrap) */
.form-check-input:checked {
    background-color: #5b2c8a !important;
    border-color: #5b2c8a !important;
}

.form-check-input:focus {
    border-color: #5b2c8a !important;
    box-shadow: 0 0 0 0.2rem rgba(91, 44, 138, 0.25) !important;
}

/* Для чекбоксов внутри таблиц и модалок */
input[type="checkbox"].form-check-input:checked {
    background-color: #5b2c8a !important;
    border-color: #5b2c8a !important;
}
'''

if '.form-check-input:checked' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для фиолетовых чекбоксов (Bootstrap) добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Чекбоксы должны стать фиолетовыми."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force purple color for checked checkboxes (Bootstrap override)"
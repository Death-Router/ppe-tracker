#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Уменьшаем вертикальные отступы в навбаре..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Уменьшаем вертикальные отступы в навбаре */
.navbar {
    padding-top: 0.25rem !important;
    padding-bottom: 0.25rem !important;
}

.navbar .container-fluid {
    padding-top: 0 !important;
    padding-bottom: 0 !important;
}

/* Убираем лишние отступы у ссылок и иконок */
.navbar-nav .nav-link {
    padding-top: 0.25rem !important;
    padding-bottom: 0.25rem !important;
}

/* Для логотипа-шестеренки */
.navbar-brand {
    padding-top: 0 !important;
    padding-bottom: 0 !important;
    margin-right: 1rem;
}
'''

if '/* Уменьшаем вертикальные отступы в навбаре */' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для компактного навбара добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навбар стал компактнее по вертикали."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: reduce vertical padding in navbar for compact look"
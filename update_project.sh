#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Увеличиваем иконку настроек в 2 раза..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Увеличиваем размер иконки настроек (было 1.5rem, стало 3rem)
old_icon = '<a class="navbar-brand text-brand-orange" href="/settings" title="Настройки" style="font-size: 1.5rem;">'
new_icon = '<a class="navbar-brand text-brand-orange" href="/settings" title="Настройки" style="font-size: 3rem;">'

if old_icon in content:
    content = content.replace(old_icon, new_icon)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Размер иконки настроек увеличен до 3rem.")
else:
    print("⚠️ Не удалось найти иконку настроек в base.html.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иконка настроек теперь в два раза больше."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: double size of settings gear icon"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Выравниваем иконки в навбаре через flexbox..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Выравнивание иконок и текста в навбаре */
.navbar-nav .nav-link {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: flex-end; /* Прижимаем к низу, чтобы иконки были на одном уровне */
    height: 100%;
    padding-bottom: 5px;
}

/* Фиксируем высоту иконок */
.navbar-nav .nav-link i,
.navbar-nav .nav-link svg {
    height: 1.8rem !important;
    width: 1.8rem !important;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 2px;
}

/* Текст под иконкой */
.navbar-nav .nav-link span {
    line-height: 1.2;
    font-size: 0.85rem;
    margin-top: 2px;
}
'''

# Удаляем старые правила для .nav-icon (если есть) и заменяем на новые
import re
content = re.sub(r'/\* Выравнивание иконок в навбаре \*/.*?\.nav-icon \{[^}]*\}', '', content, flags=re.DOTALL)
content = re.sub(r'/\* Выравнивание иконок и текста в навбаре \*/.*?\.navbar-nav \.nav-link span \{[^}]*\}', '', content, flags=re.DOTALL)

content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS для выравнивания иконок обновлен.")
PYEOF

echo "🔧 Убираем лишние классы и стили из base.html (чтобы не мешали)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Убираем класс nav-icon и inline-стили height, чтобы все иконки управлялись только CSS
content = content.replace(' class="d-block mx-auto mb-1 nav-icon"', ' class="d-block mx-auto mb-1"')
content = content.replace(' style="height: 1.8rem;"', '')
content = content.replace(' style="font-size: 1.8rem; height: 1.8rem;"', ' style="font-size: 1.8rem;"')

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ base.html очищен от лишних стилей.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иконки должны выровняться."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: align navbar icons with flexbox (equal height, bottom alignment)"
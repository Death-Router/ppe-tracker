#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Меняем цвет кнопок 'Удалить' на оранжевый (как шапки таблиц)..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Заменяем стили для btn-outline-danger на оранжевые
new_css = '''
/* Кнопки "Удалить" (корзина) — оранжевые (как шапки таблиц) */
.btn-outline-danger {
    color: #FF6600 !important;
    border-color: #FF6600 !important;
}
.btn-outline-danger:hover {
    background-color: #FF6600 !important;
    color: #fff !important;
    border-color: #FF6600 !important;
}
'''

# Удаляем старые правила для .btn-outline-danger, если они есть
import re
content = re.sub(r'/\* Кнопки удаления.*?\.btn-outline-danger \{[^}]*\}.*?\.btn-outline-danger:hover \{[^}]*\}', '', content, flags=re.DOTALL)

# Добавляем новые
content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS для кнопок 'Удалить' обновлен (оранжевый).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки 'Удалить' теперь оранжевые."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: change delete buttons color to orange"
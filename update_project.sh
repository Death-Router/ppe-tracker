#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Исправляем CSS для оранжевых шапок таблиц (добавляем !important)..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Удаляем старый блок .bg-brand-orange, если он есть
import re
content = re.sub(r'/\* Фирменный оранжевый Ростелекома для шапок таблиц \*/.*?\.table thead\.bg-brand-orange th \{[^}]*\}', '', content, flags=re.DOTALL)

# Добавляем новый, более мощный CSS
brand_orange_css = '''
/* Фирменный оранжевый Ростелекома для шапок таблиц */
.table thead.bg-brand-orange th,
.bg-brand-orange {
    background-color: #FF6600 !important;
    color: #ffffff !important;
    border-bottom: none !important;
}

/* Убираем серый фон из Bootstrap, если он перебивает */
.table > :not(caption) > * > * {
    background-color: inherit !important;
}
'''
content += brand_orange_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS обновлен (добавлен !important для оранжевого фона).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шапки таблиц теперь оранжевые."
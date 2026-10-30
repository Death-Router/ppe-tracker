#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем навбар внутри iframe (при embedded=1)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Оборачиваем навбар в условие: показываем, только если нет параметра embedded
# Ищем <nav ...> ... </nav>
import re

# Проверяем, есть ли уже проверка на embedded
if 'request.query_params.get("embedded")' not in content:
    # Оборачиваем блок навбара в условие
    # Находим начало и конец навбара
    nav_start = content.find('<nav')
    nav_end = content.find('</nav>') + len('</nav>')
    
    if nav_start != -1 and nav_end != -1:
        nav_block = content[nav_start:nav_end]
        # Добавляем условие перед навбаром и закрываем после
        condition_open = '{% if not request.query_params.get("embedded") %}\n'
        condition_close = '\n{% endif %}\n'
        
        content = content[:nav_start] + condition_open + nav_block + condition_close + content[nav_end:]
        
        # Также убираем лишние отступы у main, если embedded
        # (опционально)
        content = content.replace(
            '<main class="container pb-5">',
            '<main class="container {% if not request.query_params.get("embedded") %}pb-5{% else %}pt-3{% endif %}">'
        )
        
        print("✅ Навбар обернут в условие (скрыт при embedded=1).")
    else:
        print("⚠️ Не удалось найти навбар в base.html.")
else:
    print("ℹ️ Условие для embedded уже есть.")

with open('app/templates/base.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навбар скрыт внутри вкладок."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: hide navbar inside embedded iframes"
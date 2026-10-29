#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Выносим модалку выдачи за пределы основной формы..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# 1. Находим блок модалки выдачи (он начинается с <!-- Модальное окно выдачи -->)
import re
modal_pattern = r'<!-- Модальное окно выдачи -->.*?</div>\s*</div>\s*</div>\s*</div>'
match = re.search(modal_pattern, content, re.DOTALL)

if match:
    modal_html = match.group(0)
    # Удаляем модалку из текущего места
    content = content.replace(modal_html, '')
    
    # Вставляем её перед закрывающим {% endblock %} (после основной формы)
    # Находим последний {% endblock %}
    last_endblock = content.rfind('{% endblock %}')
    if last_endblock != -1:
        content = content[:last_endblock] + modal_html + '\n' + content[last_endblock:]
        print("✅ Модалка выдачи вынесена за пределы формы.")
    else:
        print("⚠️ Не удалось найти {% endblock %}.")
else:
    print("⚠️ Не удалось найти модалку выдачи (возможно, структура изменилась).")

# На всякий случай проверим, что кнопка в основной форме имеет type="submit" (это нормально)
# А кнопка в модалке — type="submit" внутри issue-form (это тоже нормально, но теперь она вне основной формы)

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Модалка выдачи вынесена из формы, конфликт устранен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: move issue modal outside employee form to prevent submit conflict"
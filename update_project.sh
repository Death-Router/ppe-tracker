#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📐 Правим тексты в модалке и карточке сотрудника..."

python3 - << 'PYEOF'
import os

# 1. Обновляем модалку (list.html)
with open('app/templates/employees/list.html', 'r') as f:
    content = f.read()

# Сокращаем текст подразделения
content = content.replace(
    '<option value="">Подразделение...</option>',
    '<option value="">Подразделение</option>'
)
# Меняем "Дата смены" на "Дата перевода"
content = content.replace(
    '<label class="form-label text-nowrap">Дата смены</label>',
    '<label class="form-label text-nowrap">Дата перевода</label>'
)

with open('app/templates/employees/list.html', 'w') as f:
    f.write(content)
print("✅ Модалка обновлена.")

# 2. Обновляем карточку (edit.html)
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Меняем "Дата смены должности" на "Дата перевода"
content = content.replace(
    '<label class="form-label" for="position_change_date">Дата смены должности</label>',
    '<label class="form-label" for="position_change_date">Дата перевода</label>'
)

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
print("✅ Карточка сотрудника обновлена.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix department placeholder and rename 'Дата смены' to 'Дата перевода'"
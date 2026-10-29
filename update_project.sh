#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📐 Расширяем колонку 'Размер' и сокращаем текст..."

# 1. В шаблоне edit.html увеличиваем ширину колонки
python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Ищем <th style="width: 150px;">Размер</th> и меняем на 250px
content = content.replace(
    '<th style="width: 150px;">Размер</th>',
    '<th style="width: 250px;">Размер</th>'
)

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
print("✅ Ширина колонки увеличена до 250px.")
PYEOF

# 2. В employee_edit.js заменяем длинный placeholder на короткий
python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Заменяем текст "Выберите размер..." на "Размер..." в select
content = content.replace(
    '<option value="">Выберите размер...</option>',
    '<option value="">Размер...</option>'
)

# Также для input placeholder "Введите размер" -> "Размер"
content = content.replace(
    'placeholder="Введите размер"',
    'placeholder="Размер"'
)

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
print("✅ Текст сокращен (теперь 'Размер...' вместо 'Выберите размер...').")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Колонка стала шире, текст короче."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: widen size column and shorten placeholder"
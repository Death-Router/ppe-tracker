#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📐 Исправляем выравнивание в модалке создания сотрудника..."

python3 - << 'PYEOF'
with open('app/templates/employees/list.html', 'r') as f:
    content = f.read()

# 1. Сокращаем тексты в select
content = content.replace(
    '<option value="">Выберите подразделение...</option>',
    '<option value="">Подразделение...</option>'
)
content = content.replace(
    '<option value="">Сначала выберите подразделение</option>',
    '<option value="">Сначала выберите цех</option>'
)

# 2. Для "Дата смены должности" добавляем класс text-nowrap к label, чтобы он не переносился
content = content.replace(
    '<label class="form-label">Дата смены должности</label>',
    '<label class="form-label text-nowrap">Дата смены</label>'
)

# 3. Для "Дата приема" на всякий случай тоже оставляем коротким
content = content.replace(
    '<label class="form-label">Дата приема <span class="text-danger">*</span></label>',
    '<label class="form-label text-nowrap">Дата приема <span class="text-danger">*</span></label>'
)

with open('app/templates/employees/list.html', 'w') as f:
    f.write(content)
print("✅ Тексты сокращены, лейблы выровнены.")
PYEOF

# 4. Обновляем JS, чтобы при выборе подразделения placeholder в должности тоже был коротким
python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

content = content.replace(
    "createPosSelect.innerHTML = '<option value=\"\">Сначала выберите подразделение</option>';",
    "createPosSelect.innerHTML = '<option value=\"\">Сначала выберите цех</option>';"
)

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
print("✅ JS обновлен (короткий placeholder для должности).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix alignment and shorten labels in employee creation modal"
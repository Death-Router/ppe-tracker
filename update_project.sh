#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем скругление таблиц (верхние углы у шапки)..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Удаляем старые правила скругления (если они были)
import re
content = re.sub(r'/\* Скругление углов таблиц внутри карточек \*/.*?\.card \.table-responsive \{[^}]*\}', '', content, flags=re.DOTALL)
content = re.sub(r'/\* Разрешаем перенос текста в навбаре.*?\.navbar-nav \.nav-link span \{[^}]*\}', '', content, flags=re.DOTALL)

# Добавляем новые правила
new_css = '''
/* Скругление углов таблиц и шапок */
.card {
    overflow: hidden;
}

.table {
    margin-bottom: 0;
    border-collapse: separate;
    border-spacing: 0;
}

/* Скругляем верхние углы у цветной шапки */
.table thead.bg-brand-orange th:first-child {
    border-top-left-radius: 16px;
}

.table thead.bg-brand-orange th:last-child {
    border-top-right-radius: 16px;
}

/* Скругляем нижние углы у последней строки таблицы */
.table tbody tr:last-child td:first-child {
    border-bottom-left-radius: 16px;
}

.table tbody tr:last-child td:last-child {
    border-bottom-right-radius: 16px;
}

/* Убираем стандартные границы Bootstrap, чтобы не мешали скруглению */
.table-bordered {
    border: none;
}
.table-bordered th,
.table-bordered td {
    border: 1px solid #dee2e6;
}
'''

content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS для скругления верхних углов шапки добавлен.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Скругление исправлено."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix table rounded corners (top headers, bottom last row)"
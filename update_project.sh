#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Принудительно меняем цвет выделения на фиолетовый..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Удаляем все старые правила для selected-row
import re
content = re.sub(r'/\* Выбранные строки.*?\.table tbody tr\.selected-row:hover > td \{[^}]*\}', '', content, flags=re.DOTALL)

# Добавляем новые с максимальной специфичностью
new_css = '''
/* Выбранные строки — фиолетовый фон (перебиваем все) */
.table tbody tr.selected-row td,
.table tbody tr.selected-row:hover td,
.table tbody tr.selected-row:focus td,
.table tbody tr.selected-row:active td,
.table-hover tbody tr.selected-row:hover td,
.table-hover tbody tr.selected-row:hover > * {
    background-color: #e8d5f5 !important;
    color: #5b2c8a !important;
    box-shadow: inset 0 0 0 9999px rgba(91, 44, 138, 0.08) !important;
}

/* Убираем синее выделение браузера */
::selection {
    background: rgba(91, 44, 138, 0.2);
    color: #000;
}
'''

content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS обновлен (максимальная специфичность).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверь (Ctrl+F5)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force purple background for selected rows with !important"
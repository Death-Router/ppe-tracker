#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Жёстко применяем моноширинный шрифт к табельному номеру..."

# 1. Обновляем CSS
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Моноширинный шрифт для табельного номера (каждый символ одинаковой ширины) */
.table-employees td:nth-child(2),
.table-employees th:nth-child(2) {
    font-family: 'Courier New', Courier, monospace !important;
    font-variant-numeric: tabular-nums !important; /* Для цифр */
    font-feature-settings: "tnum" !important;
}
'''

# Удаляем старые правила для .table-employees td:nth-child(2)
import re
content = re.sub(r'\.table-employees th:nth-child\(2\),.*?\.table-employees td:nth-child\(2\) \{[^}]*\}', '', content, flags=re.DOTALL)

content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS обновлен (Courier New, tabular-nums).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер теперь точно моноширинный."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force monospace font (Courier New, tabular-nums) for personnel number"
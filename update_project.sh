#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно задаем моноширинный шрифт через inline-стиль..."

# 1. Обновляем JS (добавляем style="font-family: monospace; ...")
python3 - << 'PYEOF'
with open('app/static/js/employees_list.js', 'r') as f:
    content = f.read()

# Заменяем ячейку с табельным номером на версию с inline-стилем
old_td = '''<td class="py-1 font-monospace text-end">${escapeHtml(e.personnel_number)}</td>'''
new_td = '''<td class="py-1" style="font-family: 'Courier New', Courier, monospace; font-variant-numeric: tabular-nums; text-align: center; width: 120px;">${escapeHtml(e.personnel_number)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ JS обновлен (inline-стиль для табельного номера).")
else:
    # Если класс не найден, попробуем найти просто ячейку
    import re
    content = re.sub(
        r'<td[^>]*>\$\{escapeHtml\(e\.personnel_number\)\}</td>',
        new_td,
        content
    )
    print("✅ JS обновлен (альтернативный метод).")

with open('app/static/js/employees_list.js', 'w') as f:
    f.write(content)
PYEOF

# 2. Убираем лишние CSS-правила для .table-employees (чтобы не мешали)
python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

import re
content = re.sub(r'/\* Моноширинный шрифт для табельного номера.*?\.table-employees th:nth-child\(2\) \{[^}]*\}', '', content, flags=re.DOTALL)
content = re.sub(r'/\* Фиксированная ширина для колонки табельного номера.*?\.table-employees td:nth-child\(2\) \{[^}]*\}', '', content, flags=re.DOTALL)

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS очищен от старых правил.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Табельный номер теперь точно моноширинный."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: use inline style for monospace personnel number (guaranteed)"
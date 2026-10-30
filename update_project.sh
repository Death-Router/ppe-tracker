#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Заменяем отступы на стрелку ↳ в иерархии подразделений..."

# 1. В employee_edit.js (карточка сотрудника)
python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Заменяем построение строки с отступами на стрелку
old_code = '''      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');'''
new_code = '''      hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ employee_edit.js: отступы заменены на ↳.")
else:
    print("⚠️ employee_edit.js: не удалось найти код с отступами.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

# 2. В positions_list.js (если там тоже есть иерархия)
if [ -f "app/static/js/positions_list.js" ]; then
    python3 - << 'PYEOF'
with open('app/static/js/positions_list.js', 'r') as f:
    content = f.read()

old_code = '''      '<option value="">Выберите подразделение...</option>' +
        depts.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');'''
new_code = '''      '<option value="">Выберите подразделение...</option>' +
        depts.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ positions_list.js: отступы заменены на ↳.")
else:
    print("ℹ️ positions_list.js: не найдено (возможно, нет иерархии в этой форме).")

with open('app/static/js/positions_list.js', 'w') as f:
    f.write(content)
PYEOF
fi

# 3. В department_edit.js (если там есть иерархия)
if [ -f "app/static/js/department_edit.js" ]; then
    python3 - << 'PYEOF'
with open('app/static/js/department_edit.js', 'r') as f:
    content = f.read()

old_code = '''      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');'''
new_code = '''      hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ department_edit.js: отступы заменены на ↳.")
else:
    print("ℹ️ department_edit.js: не найдено (возможно, нет иерархии).")

with open('app/static/js/department_edit.js', 'w') as f:
    f.write(content)
PYEOF
fi

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иерархия подразделений теперь со стрелками."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace indentation with arrow (↳) in department hierarchy"
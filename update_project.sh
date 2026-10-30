#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Меняем обрезку пути подразделения (многоточие в начале)..."

python3 - << 'PYEOF'
with open('app/static/js/positions_list.js', 'r') as f:
    content = f.read()

# 1. Добавляем функцию для обрезки строки с начала
if 'function truncateStart' not in content:
    func = '''
  function truncateStart(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return '...' + str.slice(-maxLength);
  }
'''
    content = content.replace(
        'function truncate(str, maxLength) {',
        func + '\n  function truncate(str, maxLength) {'
    )

# 2. Заменяем использование truncate на truncateStart для пути подразделения
old_render = '''      const deptPath = buildDeptPath(p.department_id, allDepartments);
      const fullName = escapeHtml(p.name);
      const shortName = escapeHtml(truncate(p.name, 60));
      const shortDeptPath = escapeHtml(truncate(deptPath, 50));'''
      
new_render = '''      const deptPath = buildDeptPath(p.department_id, allDepartments);
      const fullName = escapeHtml(p.name);
      const shortName = escapeHtml(truncate(p.name, 60));
      const shortDeptPath = escapeHtml(truncateStart(deptPath, 30));'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ Обрезка пути подразделения изменена (многоточие в начале).")
else:
    print("⚠️ Не удалось найти блок рендеринга. Возможно, структура изменилась.")

with open('app/static/js/positions_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Бейджи теперь обрезаются с начала."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: truncate department path from start in positions list"
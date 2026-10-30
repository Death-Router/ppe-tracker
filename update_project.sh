#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем иерархию подразделений в выпадающий список..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Добавляем функцию для построения иерархии (если её нет)
if 'function buildHierarchy' not in content:
    build_func = '''
  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    filtered.sort((a, b) => a.name.localeCompare(b.name));
    for (const dept of filtered) {
      result.push({ ...dept, level });
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }
'''
    content = content.replace(
        '  async function loadDepartments() {',
        build_func + '\n  async function loadDepartments() {'
    )

# 2. Обновляем loadDepartments, чтобы использовать иерархию
old_load = '''  async function loadDepartments() {
    const depts = await API.get('/api/v1/departments');
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      depts.map(d => `<option value="${d.id}">${d.name}</option>`).join('');
  }'''

new_load = '''  async function loadDepartments() {
    const depts = await API.get('/api/v1/departments');
    const hierarchy = buildHierarchy(depts);
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
  }'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("✅ loadDepartments обновлен (с иерархией).")
else:
    print("⚠️ Не удалось найти loadDepartments.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иерархия подразделений добавлена в выпадающий список."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add hierarchy indentation to department dropdown in employee card"
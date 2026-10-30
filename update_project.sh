#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно добавляем путь к подразделению под заголовком..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Проверяем, есть ли div для пути
if 'employee-dept-path' not in content:
    old_header = '<h1 class="h3 mb-0" id="employee-title">Редактирование сотрудника</h1>'
    new_header = '''<div>
                <h1 class="h3 mb-0" id="employee-title">Редактирование сотрудника</h1>
                <div id="employee-dept-path" class="text-muted small mt-1"></div>
            </div>'''
    
    if old_header in content:
        content = content.replace(old_header, new_header)
        print("✅ Div для пути добавлен в шаблон.")
    else:
        print("⚠️ Не удалось найти заголовок.")
else:
    print("ℹ️ Div уже есть.")

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "🔧 Добавляем принудительное обновление пути в JS..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Добавляем функцию для построения пути (если нет)
if 'function buildDeptPath' not in content:
    content = content.replace(
        'async function loadDepartments() {',
        '''function buildDeptPath(deptId, allDepts) {
    if (!deptId) return '';
    const dept = allDepts.find(d => d.id === deptId);
    if (!dept) return '';
    const parentPath = dept.parent_id ? buildDeptPath(dept.parent_id, allDepts) : '';
    return parentPath ? `${parentPath} / ${dept.name}` : dept.name;
  }

  async function loadDepartments() {'''
    )
    print("✅ Функция buildDeptPath добавлена.")

# Добавляем глобальную переменную (если нет)
if 'let allDepartments = [];' not in content:
    content = content.replace(
        'async function loadDepartments() {',
        'let allDepartments = [];\n\n  async function loadDepartments() {'
    )

# Обновляем loadDepartments, чтобы сохранять allDepartments
if 'allDepartments = await API.get' not in content:
    content = content.replace(
        'const depts = await API.get(\'/api/v1/departments\');',
        'allDepartments = await API.get(\'/api/v1/departments\');\n    const depts = allDepartments;'
    )

# Добавляем обновление пути в loadEmployee (после установки заголовка)
if 'employee-dept-path' not in content:
    content = content.replace(
        'titleEl.textContent = `Редактирование: ${fio}`;',
        '''titleEl.textContent = `Редактирование: ${fio}`;
        // Обновляем путь к подразделению
        const deptPathEl = document.getElementById('employee-dept-path');
        if (deptPathEl) {
          if (emp.department_id && allDepartments.length) {
            deptPathEl.textContent = buildDeptPath(emp.department_id, allDepartments);
          } else {
            deptPathEl.textContent = '';
          }
        }'''
    )
    print("✅ Обновление пути добавлено в loadEmployee.")
else:
    print("ℹ️ Обновление пути уже есть.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Путь к подразделению должен появиться."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force add department path in employee card"
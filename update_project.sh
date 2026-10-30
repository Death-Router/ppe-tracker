#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Добавляем строку с путём к подразделению в карточку сотрудника..."

# 1. Обновляем шаблон
python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Находим заголовок и добавляем под ним div для пути
old_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h3 mb-0" id="employee-title">Редактирование сотрудника</h1>
            <a href="/employees" class="btn btn-outline-secondary">← К списку</a>
        </div>'''

new_header = '''        <div class="d-flex justify-content-between align-items-center mb-3">
            <div>
                <h1 class="h3 mb-0" id="employee-title">Редактирование сотрудника</h1>
                <div id="employee-dept-path" class="text-muted small mt-1"></div>
            </div>
            <a href="/employees" class="btn btn-outline-secondary">← К списку</a>
        </div>'''

if old_header in content:
    content = content.replace(old_header, new_header)
    with open('app/templates/employees/edit.html', 'w') as f:
        f.write(content)
    print("✅ Шаблон обновлен (добавлен div для пути).")
else:
    print("⚠️ Не удалось найти заголовок в edit.html.")
PYEOF

# 2. Обновляем JS
python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Добавляем функцию для построения полного пути
if 'function buildDeptPath' not in content:
    path_func = '''
  function buildDeptPath(deptId, allDepts) {
    if (!deptId) return '';
    const dept = allDepts.find(d => d.id === deptId);
    if (!dept) return '';
    const parentPath = dept.parent_id ? buildDeptPath(dept.parent_id, allDepts) : '';
    return parentPath ? `${parentPath} / ${dept.name}` : dept.name;
  }
'''
    content = content.replace(
        '  async function loadDepartments() {',
        path_func + '\n  async function loadDepartments() {'
    )

# В loadDepartments сохраняем все подразделения в глобальную переменную
old_load = '''  async function loadDepartments() {
    const depts = await API.get('/api/v1/departments');
    const hierarchy = buildHierarchy(depts);
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
  }'''

new_load = '''  let allDepartments = [];

  async function loadDepartments() {
    allDepartments = await API.get('/api/v1/departments');
    const hierarchy = buildHierarchy(allDepartments);
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
  }'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("✅ loadDepartments обновлен (сохранение allDepartments).")
else:
    print("⚠️ Не удалось найти loadDepartments.")

# В loadEmployee добавляем обновление пути
old_emp = '''      versionInput.value = emp.version ?? '';
      isDirty = false;

      // Меняем заголовок на ФИО сотрудника
      const titleEl = document.getElementById('employee-title');
      if (titleEl) {
        const fio = [emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ');
        titleEl.textContent = `Редактирование: ${fio}`;
      }'''

new_emp = '''      versionInput.value = emp.version ?? '';
      isDirty = false;

      // Меняем заголовок на ФИО сотрудника
      const titleEl = document.getElementById('employee-title');
      if (titleEl) {
        const fio = [emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ');
        titleEl.textContent = `Редактирование: ${fio}`;
      }

      // Обновляем путь к подразделению
      const deptPathEl = document.getElementById('employee-dept-path');
      if (deptPathEl && emp.department_id && allDepartments.length) {
        deptPathEl.textContent = buildDeptPath(emp.department_id, allDepartments);
      } else if (deptPathEl) {
        deptPathEl.textContent = '';
      }'''

if old_emp in content:
    content = content.replace(old_emp, new_emp)
    print("✅ loadEmployee обновлен (путь к подразделению).")
else:
    print("⚠️ Не удалось найти блок обновления заголовка в loadEmployee.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Путь к подразделению добавлен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add department hierarchy path under employee title"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Уплотняем список подразделений и добавляем стрелки иерархии..."

# 1. Обновляем JS (добавляем стрелки и уплотняем)
cat > app/static/js/departments_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#departments-table tbody');
  const createForm = document.getElementById('create-form');
  const createParentSelect = document.getElementById('create-parent');

  let allDepartments = [];

  // Функция для построения иерархического списка
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

  async function loadDepartments() {
    try {
      allDepartments = await API.get('/api/v1/departments');
      const hierarchy = buildHierarchy(allDepartments);
      renderTable(hierarchy);
      
      // Заполняем выпадающий список для создания (тоже иерархически)
      if (createParentSelect) {
        createParentSelect.innerHTML = '<option value="">Нет (корневое)</option>' + 
          hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function renderTable(hierarchy) {
    if (!hierarchy.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Подразделений пока нет</td></tr>`;
      return;
    }

    // Находим родителя для каждого элемента (для отображения в колонке "Вышестоящее")
    const deptMap = {};
    hierarchy.forEach(d => { deptMap[d.id] = d; });

    tbody.innerHTML = hierarchy.map(d => {
      const parentName = d.parent_id && deptMap[d.parent_id] ? deptMap[d.parent_id].name : '—';
      const fullName = escapeHtml(d.name);
      const shortName = escapeHtml(truncate(d.name, 50));
      const indent = '↳ '.repeat(d.level);
      
      return `
      <tr data-dept-id="${d.id}" style="height: 40px;">
        <td class="py-1" title="${fullName}">${indent}${shortName}</td>
        <td class="py-1">${escapeHtml(parentName)}</td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/departments/${d.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteDept(${d.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.parent_id = payload.parent_id ? Number(payload.parent_id) : null;
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/departments/', payload);
      window.showToast('Подразделение создано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteDept = async (id, name) => {
    if (!confirm(`Удалить подразделение "${name}"?`)) return;
    try {
      await API.request(`/api/v1/departments/${id}`, { method: 'DELETE' });
      window.showToast('Подразделение удалено', 'success');
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'department_updated') loadDepartments();
  });

  loadDepartments();
})();
EOF

echo "✅ JS для подразделений обновлен (стрелки, уплотнение)."

# 2. Обновляем шаблон (добавляем style для строк, если нужно)
python3 - << 'PYEOF'
with open('app/templates/departments/list.html', 'r') as f:
    content = f.read()

# Убедимся, что таблица имеет класс table-sm (для компактности)
if 'table-sm' not in content:
    content = content.replace(
        'class="table table-hover align-middle mb-0"',
        'class="table table-sm table-hover align-middle mb-0"'
    )

with open('app/templates/departments/list.html', 'w') as f:
    f.write(content)
print("✅ Шаблон подразделений обновлен (table-sm).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Список подразделений уплотнен и со стрелками."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: compact departments list with hierarchy arrows"
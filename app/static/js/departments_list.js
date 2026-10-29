(() => {
  const tbody = document.querySelector('#departments-table tbody');
  const createForm = document.getElementById('create-form');
  const createParentSelect = document.getElementById('create-parent');

  // Функция для построения иерархического списка
  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    
    // Сортируем по имени для стабильности
    filtered.sort((a, b) => a.name.localeCompare(b.name));

    for (const dept of filtered) {
      result.push({ ...dept, level });
      // Рекурсивно добавляем детей
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }

  async function loadDepartments() {
    try {
      const depts = await API.get('/api/v1/departments');
      const hierarchy = buildHierarchy(depts);
      renderTable(hierarchy);
      
      // Заполняем выпадающий список для создания (тоже иерархически)
      if (createParentSelect) {
        createParentSelect.innerHTML = '<option value="">Нет (корневое)</option>' + 
          hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }

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
      const indent = '&nbsp;'.repeat(d.level * 4);
      
      return `
      <tr data-dept-id="${d.id}">
        <td><span style="display:inline-block; padding-left: ${d.level * 20}px;">${escapeHtml(d.name)}</span></td>
        <td>${escapeHtml(parentName)}</td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/departments/${d.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteDept(${d.id}, '${escapeHtml(d.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
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

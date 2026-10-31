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
      tbody.innerHTML = `<tr><td colspan="3" class="state state--error">Ошибка: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  function escapeHtml(s) {
    return String(s ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function renderTable(hierarchy) {
    if (!hierarchy.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="state">Подразделений пока нет</td></tr>`;
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
      <tr data-dept-id="${d.id}">
        <td title="${fullName}">${indent}${shortName}</td>
        <td class="cell-muted">${escapeHtml(parentName)}</td>
        <td class="col-actions">
          <a class="btn btn-icon" href="/departments/${d.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-icon btn-icon--danger js-delete-dept" data-id="${d.id}" data-name="${fullName}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  // Имя передаём через data-атрибут: в onclick оно ломалось на кавычках
  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('.js-delete-dept');
    if (!btn) return;
    window.deleteDept(Number(btn.dataset.id), btn.dataset.name);
  });

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
      window.FormValidation.refresh();
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

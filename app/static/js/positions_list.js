(() => {
  const tbody = document.querySelector('#positions-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');

  // Имя/название передаём через data-атрибуты: в onclick строка с кавычкой
  // ломала разметку и позволяла внедрить код (данные приходят из Excel-импорта).
  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('[data-action]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const name = btn.dataset.name || '';
    if (btn.dataset.action === 'delete') window.deletePos(id, name);
  });

  let allPositions = [];
  let allDepartments = [];

  // Функция для построения полного пути к подразделению
  function buildDeptPath(deptId, depts) {
    if (!deptId) return '';
    const dept = depts.find(d => d.id === deptId);
    if (!dept) return '';
    const parentPath = dept.parent_id ? buildDeptPath(dept.parent_id, depts) : '';
    return parentPath ? `${parentPath} / ${dept.name}` : dept.name;
  }

  async function loadData() {
    try {
      allPositions = await API.get('/api/v1/positions');
      allDepartments = await API.get('/api/v1/departments');
      
      // Заполняем выпадающий список подразделений в модалке
      if (createDeptSelect) {
        const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
        createDeptSelect.innerHTML = '<option value="">Выберите подразделение...</option>' +
          sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
      }
      
      renderTable(allPositions);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="state state--error">Ошибка: ${err.message}</td></tr>`;
    }
  }

  
  function truncateStart(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return '...' + str.slice(-maxLength);
  }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function renderTable(positions) {
    if (!positions.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="state">Должностей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = positions.map(p => {
      // Строим полный путь к подразделению
      const deptPath = buildDeptPath(p.department_id, allDepartments);
      const fullName = escapeHtml(p.name);
      const shortName = escapeHtml(truncate(p.name, 60));
      const shortDeptPath = escapeHtml(truncateStart(deptPath, 80));
      
      return `
      <tr data-pos-id="${p.id}">
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1" title="${escapeHtml(deptPath)}">
          <span class="badge-soft badge-purple">${shortDeptPath || '—'}</span>
        </td>
        <td class="col-actions">
          <a class="btn btn-icon" href="/positions/${p.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${p.id}" data-name="${fullName}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.department_id = Number(payload.department_id);
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/positions/', payload);
      window.showToast('Должность создана', 'success');
      bootstrap.Modal.getOrCreateInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

  window.deletePos = async (id, name) => {
    if (!confirm(`Удалить должность "${name}"?`)) return;
    try {
      await API.request(`/api/v1/positions/${id}`, { method: 'DELETE' });
      window.showToast('Должность удалена', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'position_updated') loadData();
  });

  loadData();
})();

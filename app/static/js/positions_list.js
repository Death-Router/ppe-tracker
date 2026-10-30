(() => {
  const tbody = document.querySelector('#positions-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');

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
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }

  
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
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Должностей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = positions.map(p => {
      // Строим полный путь к подразделению
      const deptPath = buildDeptPath(p.department_id, allDepartments);
      const fullName = escapeHtml(p.name);
      const shortName = escapeHtml(truncate(p.name, 60));
      const shortDeptPath = escapeHtml(truncateStart(deptPath, 50));
      
      return `
      <tr data-pos-id="${p.id}" style="height: 40px;">
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1" title="${escapeHtml(deptPath)}">
          <span class="badge bg-purple">${shortDeptPath || '—'}</span>
        </td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/positions/${p.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deletePos(${p.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
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
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
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

(() => {
  const tbody = document.querySelector('#positions-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');

  async function loadPositions() {
    try {
      const positions = await API.get('/api/v1/positions');
      renderTable(positions);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadDepartmentsForSelect() {
    try {
      const depts = await API.get('/api/v1/departments');
      createDeptSelect.innerHTML = '<option value="">Выберите подразделение...</option>' +
        depts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
    } catch (err) {
      createDeptSelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(positions) {
    if (!positions.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Должностей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = positions.map(p => `
      <tr data-pos-id="${p.id}">
        <td><strong>${escapeHtml(p.name)}</strong></td>
        <td><span class="badge bg-secondary">${escapeHtml(p.department?.name ?? '—')}</span></td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/positions/${p.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deletePos(${p.id}, '${escapeHtml(p.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
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
      loadPositions();
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
      loadPositions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'position_updated') loadPositions();
  });

  loadDepartmentsForSelect();
  loadPositions();
})();

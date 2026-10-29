(() => {
  const tbody = document.querySelector('#departments-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadDepartments() {
    try {
      const depts = await API.get('/api/v1/departments');
      renderTable(depts);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(depts) {
    if (!depts.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Подразделений пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = depts.map(d => `
      <tr data-dept-id="${d.id}">
        <td>${d.id}</td>
        <td><strong>${escapeHtml(d.name)}</strong></td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/departments/${d.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteDept(${d.id}, '${escapeHtml(d.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
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

(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadGroups() {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      renderTable(groups);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(groups) {
    if (!groups.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Групп пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = groups.map(g => `
      <tr data-id="${g.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(g.name)}</strong></td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
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
      await API.post('/api/v1/ppe_size_groups/', payload);
      window.showToast('Размерная группа создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteGroup = async (id, name) => {
    if (!confirm(`Удалить размерную группу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_size_groups/${id}`, { method: 'DELETE' });
      window.showToast('Размерная группа удалена', 'success');
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  loadGroups();
})();

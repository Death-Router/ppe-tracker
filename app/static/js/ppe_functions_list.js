(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadFunctions() {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      renderTable(funcs);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(funcs) {
    if (!funcs.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Функций пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = funcs.map(f => `
      <tr data-id="${f.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(f.name)}</strong></td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
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
      await API.post('/api/v1/ppe_functions/', payload);
      window.showToast('Функция создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteFunction = async (id, name) => {
    if (!confirm(`Удалить функцию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_functions/${id}`, { method: 'DELETE' });
      window.showToast('Функция удалена', 'success');
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  loadFunctions();
})();

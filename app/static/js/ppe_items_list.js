(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createCategorySelect = document.getElementById('create-category');

  async function loadItems() {
    try {
      const items = await API.get('/api/v1/ppe_items');
      renderTable(items);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadCategoriesForSelect() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      createCategorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      createCategorySelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Наименований пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => `
      <tr data-item-id="${i.id}">
        <td><strong>${escapeHtml(i.name)}</strong></td>
        <td><span class="badge bg-secondary">${escapeHtml(i.category?.name ?? '—')}</span></td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteItem(${i.id}, '${escapeHtml(i.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_items/', payload);
      window.showToast('Наименование создано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteItem = async (id, name) => {
    if (!confirm(`Удалить наименование "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_items/${id}`, { method: 'DELETE' });
      window.showToast('Наименование удалено', 'success');
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'item_updated') loadItems();
  });

  loadCategoriesForSelect();
  loadItems();
})();

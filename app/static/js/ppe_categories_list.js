(() => {
  const tbody = document.querySelector('#categories-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadCategories() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      renderTable(categories);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(categories) {
    if (!categories.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Категорий пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = categories.map(c => `
      <tr data-category-id="${c.id}">
        <td>${c.id}</td>
        <td><strong>${escapeHtml(c.name)}</strong></td>
        <td>${escapeHtml(c.description ?? '—')}</td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/ppe-categories/${c.id}/edit">Ред.</a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteCategory(${c.id}, '${escapeHtml(c.name)}')">Удалить</button>
        </td>
      </tr>
    `).join('');
  }

  // Создание
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_categories/', payload);
      window.showToast('Категория создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // Удаление
  window.deleteCategory = async (id, name) => {
    if (!confirm(`Удалить категорию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_categories/${id}`, { method: 'DELETE' });
      window.showToast('Категория удалена', 'success');
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'category_updated') loadCategories();
  });

  loadCategories();
})();
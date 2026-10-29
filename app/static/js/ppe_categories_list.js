(() => {
  const tbody = document.querySelector('#categories-table tbody');
  const createForm = document.getElementById('create-form');
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeCategoryName = document.getElementById('size-category-name');
  const sizeCategoryIdInput = document.getElementById('size-category-id');

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
        <td><strong>${escapeHtml(c.name)}</strong></td>
        <td>${escapeHtml(c.description ?? '—')}</td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-secondary" onclick="openSizesModal(${c.id}, '${escapeHtml(c.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary" href="/ppe-categories/${c.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteCategory(${c.id}, '${escapeHtml(c.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
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

  // --- Управление размерами ---
  window.openSizesModal = async (categoryId, categoryName) => {
    sizeCategoryIdInput.value = categoryId;
    sizeCategoryName.textContent = categoryName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = new bootstrap.Modal(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      sizesList.innerHTML = `<li class="list-group-item text-danger">Ошибка: ${err.message}</li>`;
    }
  };

  function renderSizesList(sizes) {
    if (!sizes.length) {
      sizesList.innerHTML = '<li class="list-group-item text-muted">Нет добавленных размеров</li>';
      return;
    }
    sizesList.innerHTML = sizes.map(s => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `}).join('');
  }

  sizeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const categoryId = Number(sizeCategoryIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { category_id: categoryId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  window.deleteSize = async (sizeId) => {
    if (!confirm('Удалить этот размер?')) return;
    try {
      await API.request(`/api/v1/ppe_sizes/${sizeId}`, { method: 'DELETE' });
      window.showToast('Размер удален', 'success');
      const categoryId = Number(sizeCategoryIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'category_updated') loadCategories();
  });

  loadCategories();
})();

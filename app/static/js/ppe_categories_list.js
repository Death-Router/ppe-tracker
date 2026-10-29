(() => {
  const tbody = document.querySelector('#categories-table tbody');
  const createForm = document.getElementById('create-form');
  const searchInput = document.getElementById('search-input');
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeCategoryName = document.getElementById('size-category-name');
  const sizeCategoryIdInput = document.getElementById('size-category-id');

  let allCategories = [];

  async function loadCategories() {
    try {
      allCategories = await API.get('/api/v1/ppe_categories');
      filterCategories();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterCategories() {
    const searchTerm = searchInput.value.toLowerCase().trim();
    let filtered = allCategories;

    if (searchTerm) {
      filtered = filtered.filter(c => 
        c.name.toLowerCase().includes(searchTerm) || 
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }

    renderTable(filtered);
  }

  function renderTable(categories) {
    if (!categories.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = categories.map(c => {
      const fullName = escapeHtml(c.name);
      const shortName = escapeHtml(truncate(c.name, 50));
      const shortDesc = escapeHtml(truncate(c.description ?? '', 60));
      return `
      <tr data-category-id="${c.id}" style="height: 40px;">
        <td class="py-1" title="${fullName}"><strong>${shortName}</strong></td>
        <td class="py-1" title="${escapeHtml(c.description ?? '')}">${shortDesc || '—'}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-secondary py-0 px-1" onclick="openSizesModal(${c.id}, '${fullName}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-categories/${c.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteCategory(${c.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  searchInput.addEventListener('input', filterCategories);

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
      <li class="list-group-item d-flex justify-content-between align-items-center py-1">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteSize(${s.id})">✕</button>
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

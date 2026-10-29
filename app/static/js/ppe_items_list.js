(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createCategorySelect = document.getElementById('create-category');
  const searchInput = document.getElementById('search-input');
  const categoryFilter = document.getElementById('category-filter');

  let allItems = [];

  async function loadItems() {
    try {
      allItems = await API.get('/api/v1/ppe_items');
      populateCategoryFilter(allItems);
      filterItems();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
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

  function populateCategoryFilter(items) {
    const categories = [...new Set(items.map(i => i.category?.name).filter(Boolean))];
    categoryFilter.innerHTML = '<option value="">Все категории</option>' +
      categories.map(name => `<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`).join('');
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterItems() {
    const searchTerm = searchInput.value.toLowerCase().trim();
    const selectedCategory = categoryFilter.value;

    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.category?.name || '').toLowerCase().includes(searchTerm)
      );
    }

    if (selectedCategory) {
      filtered = filtered.filter(item => item.category?.name === selectedCategory);
    }

    // Сортировка по алфавиту (по названию)
    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));

    renderTable(filtered);
  }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => {
      const fullName = escapeHtml(i.name);
      const shortName = escapeHtml(truncate(i.name, 60));
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1"><span class="badge bg-secondary">${escapeHtml(i.category?.name ?? '—')}</span></td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteItem(${i.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  searchInput.addEventListener('input', filterItems);
  categoryFilter.addEventListener('change', filterItems);

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

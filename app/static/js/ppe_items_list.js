(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createFunctionSelect = document.getElementById('create-function');
  const createSizeGroupSelect = document.getElementById('create-size-group');
  const createUnitSelect = document.getElementById('create-unit');
  const searchInput = document.getElementById('search-input');
  const filterFunction = document.getElementById('filter-function');
  const filterSizeGroup = document.getElementById('filter-size-group');
  const selectAllCheckbox = document.getElementById('select-all');
  const bulkActions = document.getElementById('bulk-actions');
  const selectedCountSpan = document.getElementById('selected-count');
  const btnBulkEdit = document.getElementById('btn-bulk-edit');
  const btnBulkDelete = document.getElementById('btn-bulk-delete');

  // Элементы модалки массового редактирования
  const bulkEditModal = new bootstrap.Modal(document.getElementById('bulkEditModal'));
  const bulkFunctionSelect = document.getElementById('bulk-function');
  const bulkSizeGroupSelect = document.getElementById('bulk-size-group');
  const bulkUnitSelect = document.getElementById('bulk-unit');
  const bulkCountSpan = document.getElementById('bulk-count');

  let allItems = [];
  let selectedIds = new Set();

  async function loadItems() {
    try {
      allItems = await API.get('/api/v1/ppe_items');
      filterItems();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      const groups = await API.get('/api/v1/ppe_size_groups');
      const units = await API.get('/api/v1/units');

      // Заполняем фильтры
      if (filterFunction) {
        filterFunction.innerHTML = '<option value="">Все функции</option>' +
          functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      }
      if (filterSizeGroup) {
        filterSizeGroup.innerHTML = '<option value="">Все размерные группы</option>' +
          groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      }

      // Заполняем селекты создания
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      createUnitSelect.innerHTML = '<option value="">Не указана</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');

      // Заполняем селекты массового редактирования
      bulkFunctionSelect.innerHTML = '<option value="">Не изменять</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      bulkSizeGroupSelect.innerHTML = '<option value="">Не изменять</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      bulkUnitSelect.innerHTML = '<option value="">Не изменять</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');

    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterItems() {
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const funcId = filterFunction ? Number(filterFunction.value) : null;
    const groupId = filterSizeGroup ? Number(filterSizeGroup.value) : null;

    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.function?.name || '').toLowerCase().includes(searchTerm) ||
        (item.size_group?.name || '').toLowerCase().includes(searchTerm)
      );
    }
    if (funcId) filtered = filtered.filter(item => item.function_id === funcId);
    if (groupId) filtered = filtered.filter(item => item.size_group_id === groupId);

    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));
    renderTable(filtered);
  }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => {
      const fullName = escapeHtml(i.name);
      const shortName = escapeHtml(truncate(i.name, 60));
      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">
        <td class="py-1">
          <input type="checkbox" class="item-checkbox" value="${i.id}" ${isChecked} onchange="toggleSelection(${i.id}, this.checked)">
        </td>
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1">
          <span class="badge bg-secondary me-1">${escapeHtml(i.function?.name ?? '—')}</span>
          <span class="badge bg-info">${escapeHtml(i.size_group?.name ?? '—')}</span>
        </td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteItem(${i.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
    updateBulkPanel();
  }

  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
  };

  function updateBulkPanel() {
    const count = selectedIds.size;
    if (count > 0) {
      bulkActions.classList.remove('d-none');
      selectedCountSpan.textContent = count;
    } else {
      bulkActions.classList.add('d-none');
      selectAllCheckbox.checked = false;
    }
  }

  window.openBulkEditModal = () => {
    if (!selectedIds.size) return;
    bulkCountSpan.textContent = selectedIds.size;
    bulkFunctionSelect.value = '';
    bulkSizeGroupSelect.value = '';
    bulkUnitSelect.value = '';
    bulkEditModal.show();
  };

  window.applyBulkEdit = async () => {
    const funcId = bulkFunctionSelect.value;
    const groupId = bulkSizeGroupSelect.value;
    const unitId = bulkUnitSelect.value;

    if (!funcId && !groupId && !unitId) {
      window.showToast('Выберите хотя бы одно поле для изменения', 'warning');
      return;
    }

    try {
      await API.request('/api/v1/ppe_items/bulk', {
        method: 'PATCH',
        body: JSON.stringify({
          ids: Array.from(selectedIds),
          function_id: funcId ? Number(funcId) : null,
          size_group_id: groupId ? Number(groupId) : null,
          unit_id: unitId ? Number(unitId) : null
        })
      });
      window.showToast('Выбранные СИЗ обновлены', 'success');
      bulkEditModal.hide();
      selectedIds.clear();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  window.bulkDelete = async () => {
    if (!selectedIds.size) return;
    if (!confirm(`Удалить ${selectedIds.size} выбранных СИЗ?`)) return;

    try {
      await API.request('/api/v1/ppe_items/bulk-delete', {
        method: 'POST',
        body: JSON.stringify({ ids: Array.from(selectedIds) })
      });
      window.showToast('Выбранные СИЗ удалены', 'success');
      selectedIds.clear();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', (e) => {
      const checked = e.target.checked;
      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
      });
      updateBulkPanel();
    });
  }

  if (searchInput) searchInput.addEventListener('input', filterItems);
  if (filterFunction) filterFunction.addEventListener('change', filterItems);
  if (filterSizeGroup) filterSizeGroup.addEventListener('change', filterItems);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.function_id = payload.function_id ? Number(payload.function_id) : null;
    payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
    payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

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

  loadSelects();
  loadItems();
})();

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
  const bulkEditModal = document.getElementById('bulkEditModal');
  const bulkFunctionSelect = document.getElementById('bulk-function');
  const bulkSizeGroupSelect = document.getElementById('bulk-size-group');
  const bulkUnitSelect = document.getElementById('bulk-unit');
  const bulkCountSpan = document.getElementById('bulk-count');

  let allItems = [];

  onRowAction(tbody, {
    delete: (id, name) => window.deleteItem(id, name),
    edit: (id) => window.openEditModal(id),
  });
  let selectedIds = new Set();

  const PAGE_SIZE = 20;
  let currentPage = 1;
  let searchTimer = null;

  async function loadItems(page = currentPage) {
    currentPage = page;
    try {
      const params = new URLSearchParams({
        paginated: 'true',
        page: String(currentPage),
        page_size: String(PAGE_SIZE),
      });

      const term = searchInput ? searchInput.value.trim() : '';
      if (term) params.set('search', term);

      const funcId = filterFunction ? filterFunction.value : '';
      if (funcId) params.set('function_id', funcId);

      const groupId = filterSizeGroup ? filterSizeGroup.value : '';
      if (groupId) params.set('size_group_id', groupId);

      const data = await API.get(`/api/v1/ppe_items/?${params.toString()}`);
      allItems = data.items;

      if (!data.items.length && data.total > 0 && currentPage > 1) {
        return loadItems(currentPage - 1);
      }

      renderTable(data.items);
      Pager.render(document.getElementById('pager'), data, loadItems);
    } catch (err) {
      tableState(tbody, 4, `Ошибка: ${err.message}`, { error: true });
    }
  }

  // Фильтры теперь серверные: запрос уходит только после паузы ввода
  if (searchInput) {
    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => loadItems(1), 300);
    });
  }
  [filterFunction, filterSizeGroup].forEach((el) => {
    if (el) el.addEventListener('change', () => loadItems(1));
  });

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      const groups = await API.get('/api/v1/ppe_size_groups');
      const units = await API.get('/api/v1/units');

      // Заполняем фильтры
      if (filterFunction) {
        filterFunction.innerHTML = '<option value="">Все функции</option>' +
          functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
        window.fitSelectWidth(filterFunction);
      }
      if (filterSizeGroup) {
        filterSizeGroup.innerHTML = '<option value="">Все размерные группы</option>' +
          groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
        window.fitSelectWidth(filterSizeGroup);
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

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function renderTable(items) {
    if (!items.length) {
      tableState(tbody, 4, 'Ничего не найдено');
      return;
    }
    tbody.innerHTML = items.map(i => {
      const fullName = escapeHtml(i.name);
      const shortName = escapeHtml(truncate(i.name, 60));
      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'is-selected' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}">
        <td>
          <input type="checkbox" class="item-checkbox" value="${i.id}" ${isChecked} onchange="toggleSelection(${i.id}, this.checked)">
        </td>
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td>
          ${i.function?.name ? `<span class="badge-soft badge-purple me-1">${escapeHtml(i.function.name)}</span>` : ''}
          ${i.size_group?.name ? `<span class="badge-soft badge-orange">${escapeHtml(i.size_group.name)}</span>` : ''}
        </td>
        <td class="col-actions">
          <button class="btn btn-icon" data-action="edit" data-id="${i.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${i.id}" data-name="${fullName}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
    updateBulkPanel();
  }

  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    // Обновляем класс строки
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) row.classList.add('is-selected');
      else row.classList.remove('is-selected');
    }
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
    ModalHelper.show(bulkEditModal);
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
      ModalHelper.hide(bulkEditModal);
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

        // Подсветка — только классом, цвета живут в app.css
        const row = document.querySelector(`tr[data-item-id="${id}"]`);
        if (row) row.classList.toggle('is-selected', checked);
      });
      updateBulkPanel();
    });
  }


  const modalEl = document.getElementById('createModal');
  const submitBtn = modalEl.querySelector('button[type="submit"]');
  const versionInput = document.getElementById('item-version');

  let editingId = null;

  function openCreateModal() {
    editingId = null;
    ModalHelper.setTitle(modalEl, 'Новое наименование СИЗ');
    submitBtn.textContent = 'Создать';
    createForm.reset();
    if (versionInput) versionInput.value = '';
    ModalHelper.show(modalEl);
  }

  window.openEditModal = async (id) => {
    try {
      const item = await API.get(`/api/v1/ppe_items/${id}`);
      editingId = id;
      ModalHelper.setTitle(modalEl, 'Редактирование наименования');
      submitBtn.textContent = 'Сохранить';

      createForm.elements['name'].value = item.name ?? '';
      createForm.elements['function_id'].value = item.function_id ?? '';
      createForm.elements['size_group_id'].value = item.size_group_id ?? '';
      createForm.elements['unit_id'].value = item.unit_id ?? '';
      if (versionInput) versionInput.value = item.version ?? '';

      ModalHelper.show(modalEl);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    await FormHelper.send(createForm, async (payload) => {
      payload.function_id = payload.function_id ? Number(payload.function_id) : null;
      payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
      payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

      if (editingId) {
        payload.version = Number(versionInput.value);
        await API.put(`/api/v1/ppe_items/${editingId}`, payload);
        window.showToast('Наименование сохранено', 'success');
      } else {
        await API.post('/api/v1/ppe_items/', payload);
        window.showToast('Наименование создано', 'success');
      }
    }, {
      onSuccess: () => {
        ModalHelper.hide(modalEl);
        createForm.reset();
        loadItems();
      },
    });
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
    // Функция, размерная группа и единица измерения показаны в таблице и
    // используются фильтрами — после их правки перечитываем и справочники
    if (['function_updated', 'size_group_updated', 'unit_updated'].includes(data.event)) {
      loadSelects();
      loadItems();
    }
  });

  loadSelects();
  loadItems();
})();

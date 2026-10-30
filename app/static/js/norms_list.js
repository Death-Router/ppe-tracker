(() => {
  const tbody = document.querySelector('#norms-table tbody');
  const searchInput = document.getElementById('search-input');
  const filterPosition = document.getElementById('filter-position');
  const selectAllCheckbox = document.getElementById('select-all');
  const selectedCountSpan = document.getElementById('selected-count');
  const bulkActions = document.getElementById('bulk-actions');
  const modalElement = document.getElementById('createNormModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');
  const modalPosition = document.getElementById('modal-position');
  const itemInput = document.getElementById('norm-item-input');
  const itemIdInput = document.getElementById('norm-item-id');
  const itemsDatalist = document.getElementById('ppe-items-list');
  const createForm = document.getElementById('create-norm-form');

  let allNorms = [];
  let allPositions = [];
  let allPpeItems = [];
  let selectedIds = new Set();
  let editingNormId = null;

  // Склонения
  function formatPeriod(value, unit) {
    if (!value) return '—';
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${unit}`;
    if (unit === 'год') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} лет`;
      if (lastDigit === 1) return `${num} год`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} года`;
      return `${num} лет`;
    }
    if (unit === 'месяц') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} месяцев`;
      if (lastDigit === 1) return `${num} месяц`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} месяца`;
      return `${num} месяцев`;
    }
    return `${value} ${unit}`;
  }

  function formatUnit(value, shortName) {
    if (!shortName) return value;
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${shortName}`;
    if (shortName.toLowerCase() === 'пара') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} пар`;
      if (lastDigit === 1) return `${num} пара`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} пары`;
      return `${num} пар`;
    }
    if (shortName.toLowerCase() === 'штука' || shortName.toLowerCase() === 'шт') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} штук`;
      if (lastDigit === 1) return `${num} штука`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} штуки`;
      return `${num} штук`;
    }
    return `${num} ${shortName}`;
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  // Загрузка данных
  async function loadData() {
    try {
      allNorms = await API.get('/api/v1/position_ppe_norms');
      allPositions = await API.get('/api/v1/positions');
      allPpeItems = await API.get('/api/v1/ppe_items');
      
      // Заполняем фильтр должностей
      if (filterPosition) {
        const sortedPositions = [...allPositions].sort((a, b) => a.name.localeCompare(b.name));
        filterPosition.innerHTML = '<option value="">Все должности</option>' +
          sortedPositions.map(p => {
            const dept = p.department?.name ?? '';
            return `<option value="${p.id}">${dept} / ${escapeHtml(p.name)}</option>`;
          }).join('');
      }

      // Заполняем datalist для СИЗ
      if (itemsDatalist) {
        itemsDatalist.innerHTML = allPpeItems.map(i => 
          `<option value="${escapeHtml(i.name)}" data-id="${i.id}"></option>`
        ).join('');
      }

      // Заполняем select должностей в модалке
      if (modalPosition) {
        const sortedPositions = [...allPositions].sort((a, b) => a.name.localeCompare(b.name));
        modalPosition.innerHTML = '<option value="">Выберите должность...</option>' +
          sortedPositions.map(p => {
            const dept = p.department?.name ?? '';
            return `<option value="${p.id}">${dept} / ${escapeHtml(p.name)}</option>`;
          }).join('');
      }

      filterAndRender();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="6" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  // Фильтрация и отрисовка
  function filterAndRender() {
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const posFilter = filterPosition ? Number(filterPosition.value) : null;

    let filtered = allNorms;

    if (searchTerm) {
      filtered = filtered.filter(n => {
        const posName = n.position?.name ?? '';
        const itemName = n.ppe_item?.name ?? '';
        return posName.toLowerCase().includes(searchTerm) || itemName.toLowerCase().includes(searchTerm);
      });
    }

    if (posFilter) {
      filtered = filtered.filter(n => n.position_id === posFilter);
    }

    renderTable(filtered);
  }

  function renderTable(norms) {
    if (!norms.length) {
      tbody.innerHTML = `<tr><td colspan="6" class="text-center text-muted py-4">Норм пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = norms.map(n => {
      const isChecked = selectedIds.has(n.id) ? 'checked' : '';
      const rowClass = selectedIds.has(n.id) ? 'selected-row' : '';
      const posName = n.position?.name ?? '—';
      const deptName = n.position?.department?.name ?? '';
      const posStr = deptName ? `${deptName} / ${posName}` : posName;
      const itemName = n.ppe_item?.name ?? '—';
      const periodStr = formatPeriod(n.wear_period_value, n.wear_period_unit);
      const qtyStr = formatUnit(n.quantity, n.ppe_item?.unit?.short_name);
      return `
      <tr data-norm-id="${n.id}" class="${rowClass}" style="height: 40px;">
        <td class="py-1">
          <input type="checkbox" class="item-checkbox" value="${n.id}" ${isChecked} onchange="toggleSelection(${n.id}, this.checked)">
        </td>
        <td class="py-1"><strong>${escapeHtml(posStr)}</strong></td>
        <td class="py-1">${escapeHtml(itemName)}</td>
        <td class="py-1">${periodStr}</td>
        <td class="py-1">${qtyStr}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editNorm(${n.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteNorm(${n.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
    updateBulkPanel();
  }

  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    const row = document.querySelector(`tr[data-norm-id="${id}"]`);
    if (row) {
      const cells = row.querySelectorAll('td');
      if (checked) {
        row.classList.add('selected-row');
        cells.forEach(td => td.style.backgroundColor = 'rgba(91, 44, 138, 0.08)');
      } else {
        row.classList.remove('selected-row');
        cells.forEach(td => td.style.backgroundColor = '');
      }
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

  window.bulkDelete = async () => {
    if (!selectedIds.size) return;
    if (!confirm(`Удалить ${selectedIds.size} выбранных норм?`)) return;

    try {
      for (const id of selectedIds) {
        await API.request(`/api/v1/position_ppe_norms/${id}`, { method: 'DELETE' });
      }
      window.showToast('Выбранные нормы удалены', 'success');
      selectedIds.clear();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    itemInput.value = '';
    itemIdInput.value = '';
    modalPosition.value = '';
  };

  // Редактирование нормы
  window.editNorm = async (id) => {
    try {
      const norm = await API.get(`/api/v1/position_ppe_norms/${id}`);
      editingNormId = id;
      modalTitle.textContent = 'Редактирование нормы';
      submitBtn.textContent = 'Сохранить';

      modalPosition.value = norm.position_id;
      
      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);
      if (item) {
        itemInput.value = item.name;
        itemIdInput.value = item.id;
      }
      
      createForm.elements['wear_period_value'].value = norm.wear_period_value;
      createForm.elements['wear_period_unit'].value = norm.wear_period_unit;
      createForm.elements['quantity'].value = norm.quantity;

      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  };

  // Обработчик ввода СИЗ (datalist)
  itemInput.addEventListener('input', (e) => {
    const val = e.target.value;
    const option = Array.from(itemsDatalist.options).find(opt => opt.value === val);
    if (option) {
      itemIdInput.value = option.getAttribute('data-id');
    } else {
      itemIdInput.value = '';
    }
  });

  // Создание/обновление нормы
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = {
      position_id: Number(modalPosition.value),
      ppe_item_id: Number(itemIdInput.value),
      wear_period_value: createForm.elements['wear_period_value'].value.trim(),
      wear_period_unit: createForm.elements['wear_period_unit'].value,
      quantity: createForm.elements['quantity'].value.trim()
    };

    if (!payload.ppe_item_id) {
      window.showToast('Выберите СИЗ из списка', 'danger');
      return;
    }

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      if (editingNormId) {
        payload.version = (await API.get(`/api/v1/position_ppe_norms/${editingNormId}`)).version;
        await API.put(`/api/v1/position_ppe_norms/${editingNormId}`, payload);
        window.showToast('Норма обновлена', 'success');
      } else {
        await API.post('/api/v1/position_ppe_norms/', payload);
        window.showToast('Норма добавлена', 'success');
      }
      bootstrap.Modal.getInstance(modalElement).hide();
      createForm.reset();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // Удаление
  window.deleteNorm = async (id) => {
    if (!confirm('Удалить эту норму?')) return;
    try {
      await API.request(`/api/v1/position_ppe_norms/${id}`, { method: 'DELETE' });
      window.showToast('Норма удалена', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Выбрать все
  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', (e) => {
      const checked = e.target.checked;
      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
        const row = document.querySelector(`tr[data-norm-id="${id}"]`);
        if (row) {
          const cells = row.querySelectorAll('td');
          if (checked) {
            row.classList.add('selected-row');
            cells.forEach(td => td.style.backgroundColor = 'rgba(91, 44, 138, 0.08)');
          } else {
            row.classList.remove('selected-row');
            cells.forEach(td => td.style.backgroundColor = '');
          }
        }
      });
      updateBulkPanel();
    });
  }

  // Фильтры
  if (searchInput) searchInput.addEventListener('input', filterAndRender);
  if (filterPosition) filterPosition.addEventListener('change', filterAndRender);

  // Кнопка "Добавить" открывает модалку в режиме создания
  document.querySelector('button[data-bs-target="#createNormModal"]')?.addEventListener('click', openCreateModal);

  WS.subscribe((data) => {
    if (data.event === 'norm_updated') loadData();
  });

  loadData();
})();

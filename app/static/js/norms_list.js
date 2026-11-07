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
  const modalDepartment = document.getElementById('modal-department');
  const modalPosition = document.getElementById('modal-position');
  const itemInput = document.getElementById('norm-item-input');
  const itemIdInput = document.getElementById('norm-item-id');
  const itemsDatalist = document.getElementById('ppe-items-list');
  const createForm = document.getElementById('create-norm-form');
  const modalTypicalNorm = document.getElementById('modal-typical-norm');

  // Пункты норм нужны только для выпадающего списка в модалке нормы;
  // сам справочник живёт на отдельной вкладке /typical-norms
  let allTypicalNorms = [];

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


  // Загрузка данных
  
  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    filtered.sort((a, b) => a.name.localeCompare(b.name));
    for (const dept of filtered) {
      result.push({ ...dept, level });
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }

  const PAGE_SIZE = 20;
  let currentPage = 1;
  let searchTimer = null;

  async function loadData(page = currentPage) {
    currentPage = page;
    try {
      // Справочники нужны целиком — для выпадающих списков и datalist
      allPositions = await API.get('/api/v1/positions');
      allPpeItems = await API.get('/api/v1/ppe_items');
      const allDepartments = await API.get('/api/v1/departments');
      
      // Заполняем select подразделений в модалке (с иерархией)
      if (modalDepartment) {
        const hierarchy = buildHierarchy(allDepartments);
        modalDepartment.innerHTML = '<option value="">Выберите подразделение...</option>' +
          hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
      }
      
      // Заполняем фильтр должностей
      if (filterPosition) {
        const sortedPositions = [...allPositions].sort((a, b) => a.name.localeCompare(b.name));
        filterPosition.innerHTML = '<option value="">Все должности</option>' +
          sortedPositions.map(p => {
            const dept = p.department?.name ?? '';
            return `<option value="${p.id}">${dept} / ${escapeHtml(p.name)}</option>`;
          }).join('');
        window.fitSelectWidth(filterPosition);
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

      // Справочник пунктов норм: и в модалке нормы, и в своей таблице
      await loadTypicalNorms();

      await loadPage(currentPage);
    } catch (err) {
      tableState(tbody, 5, `Ошибка: ${err.message}`, { error: true });
    }
  }

  // Нормы грузятся страницами: фильтры и поиск считает сервер
  async function loadPage(page = currentPage) {
    currentPage = page;
    const params = new URLSearchParams({
      paginated: 'true',
      page: String(currentPage),
      page_size: String(PAGE_SIZE),
    });

    const term = searchInput ? searchInput.value.trim() : '';
    if (term) params.set('search', term);

    const posId = filterPosition ? filterPosition.value : '';
    if (posId) params.set('position_id', posId);

    const data = await API.get(`/api/v1/position_ppe_norms/?${params.toString()}`);
    allNorms = data.items;

    if (!data.items.length && data.total > 0 && currentPage > 1) {
      return loadPage(currentPage - 1);
    }

    renderTable(data.items);
    Pager.render(document.getElementById('pager'), data, loadPage);
  }

  // Обрезаем с начала: в пути «Подразделение / Должность» важнее конец
  function truncateStart(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return '…' + str.slice(-maxLength);
  }

  onRowAction(tbody, {
    edit: (id) => window.editNorm(id),
    delete: (id) => window.deleteNorm(id),
  });

  function renderTable(norms) {
    if (!norms.length) {
      tableState(tbody, 5, 'Норм пока нет');
      return;
    }
    tbody.innerHTML = norms.map(n => {
      const isChecked = selectedIds.has(n.id) ? 'checked' : '';
      const rowClass = selectedIds.has(n.id) ? 'is-selected' : '';
      const posName = n.position?.name ?? '—';
      const deptName = n.position?.department?.name ?? '';
      const posStr = deptName ? `${deptName} / ${posName}` : posName;
      // Длинный путь обрезаем спереди: важнее конец — сама должность
      const posShort = truncateStart(posStr, 60);
      const itemName = n.ppe_item?.name ?? '—';
      // Пункт норм печатается в карточке; пусто — значит норма без основания
      const clause = n.typical_norm?.clause ?? '—';
      return `
      <tr data-norm-id="${n.id}" class="${rowClass}">
        <td>
          <input type="checkbox" class="item-checkbox" value="${n.id}" ${isChecked} onchange="toggleSelection(${n.id}, this.checked)">
        </td>
        <td title="${escapeHtml(posStr)}"><strong>${escapeHtml(posShort)}</strong></td>
        <td title="${escapeHtml(itemName)}">${escapeHtml(itemName)}</td>
        <td class="cell-mono">${escapeHtml(clause)}</td>
        <td class="col-actions">
          <button class="btn btn-icon" data-action="edit" data-id="${n.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${n.id}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
    updateBulkPanel();
  }

  // Подсветка выбранной строки — только классом, цвета берутся из app.css
  function markRow(id, selected) {
    const row = document.querySelector(`tr[data-norm-id="${id}"]`);
    if (row) row.classList.toggle('is-selected', selected);
  }

  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    markRow(id, checked);
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
      // Один запрос вместо цикла: либо удалились все, либо ни одна
      const result = await API.post('/api/v1/position_ppe_norms/bulk-delete', {
        ids: [...selectedIds],
      });
      window.showToast(result?.message || 'Выбранные нормы удалены', 'success');
      selectedIds.clear();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };


  // Обработчик смены подразделения в модалке
  if (modalDepartment) {
    modalDepartment.addEventListener('change', async (e) => {
      const deptId = Number(e.target.value);
      if (!deptId) {
        modalPosition.innerHTML = '<option value="">Сначала выберите подразделение</option>';
        return;
      }
      
      try {
        const positions = await API.get('/api/v1/positions');
        const filtered = positions.filter(p => p.department_id === deptId);
        filtered.sort((a, b) => a.name.localeCompare(b.name));
        modalPosition.innerHTML = '<option value="">Выберите должность...</option>' +
          filtered.map(p => `<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('');
      } catch (err) {
        modalPosition.innerHTML = '<option value="">Ошибка загрузки</option>';
      }
    });
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    itemInput.value = '';
    itemIdInput.value = '';
    modalDepartment.value = '';
    modalPosition.innerHTML = '<option value="">Сначала выберите подразделение</option>';
    if (modalTypicalNorm) modalTypicalNorm.value = '';
    // Раньше модалку открывал data-bs-toggle на кнопке, скрипт только
    // заполнял поля. Атрибут убран из-за двойного backdrop — теперь
    // показывать обязан скрипт.
    bootstrap.Modal.getOrCreateInstance(modalElement).show();
  };

  // Редактирование нормы
  window.editNorm = async (id) => {
    try {
      const norm = await API.get(`/api/v1/position_ppe_norms/${id}`);
      editingNormId = id;
      modalTitle.textContent = 'Редактирование нормы';
      submitBtn.textContent = 'Сохранить';

      // Находим должность и её подразделение
      const pos = allPositions.find(p => p.id === norm.position_id);
      if (pos && pos.department_id && modalDepartment) {
        modalDepartment.value = pos.department_id;
        // Загружаем должности для этого подразделения
        const positions = await API.get('/api/v1/positions');
        const filtered = positions.filter(p => p.department_id === pos.department_id);
        filtered.sort((a, b) => a.name.localeCompare(b.name));
        modalPosition.innerHTML = '<option value="">Выберите должность...</option>' +
          filtered.map(p => `<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('');
        modalPosition.value = norm.position_id;
      } else if (modalPosition) {
        modalPosition.value = norm.position_id;
      }
      
      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);
      if (item) {
        itemInput.value = item.name;
        itemIdInput.value = item.id;
      }
      
      createForm.elements['wear_period_value'].value = norm.wear_period_value;
      createForm.elements['wear_period_unit'].value = norm.wear_period_unit;
      createForm.elements['quantity'].value = norm.quantity;
      // Пункт норм связан со справочником; null — «не указан»
      if (modalTypicalNorm) modalTypicalNorm.value = norm.typical_norm_id ?? '';

      bootstrap.Modal.getOrCreateInstance(modalElement).show();
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
      // Пустой пункт — это null: в карточке графа останется пустой
      typical_norm_id: modalTypicalNorm && modalTypicalNorm.value
        ? Number(modalTypicalNorm.value)
        : null,
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
      bootstrap.Modal.getOrCreateInstance(modalElement).hide();
      createForm.reset();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
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
        markRow(id, checked);
      });
      updateBulkPanel();
    });
  }

  // Фильтры
  if (searchInput) {
    searchInput.addEventListener('input', () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => loadPage(1), 300);
    });
  }
  if (filterPosition) filterPosition.addEventListener('change', () => loadPage(1));

  // Кнопка "Добавить" открывает модалку в режиме создания
  document.getElementById('btn-create-norm')?.addEventListener('click', openCreateModal);

  // --- Копирование норм с должности на должности -----------------------
  const copyModalEl = document.getElementById('copyNormsModal');
  const copySource = document.getElementById('copy-source');
  const copyTargets = document.getElementById('copy-targets');
  const copySourceHint = document.getElementById('copy-source-hint');
  const copySubmit = document.getElementById('copy-submit');

  // Сколько норм у каждой должности — для подсказки в списке источников
  function normsCountByPosition() {
    const counts = new Map();
    allNorms.forEach((n) => {
      counts.set(n.position_id, (counts.get(n.position_id) ?? 0) + 1);
    });
    return counts;
  }

  function fillCopySelects() {
    const counts = normsCountByPosition();
    const positions = [...allPositions].sort((a, b) => a.name.localeCompare(b.name, 'ru'));

    const options = positions.map((p) => {
      const dept = p.department?.name ?? '';
      const label = dept ? `${dept} / ${p.name}` : p.name;
      return { value: p.id, label };
    });

    copySource.innerHTML = '<option value="">Выберите должность-источник...</option>' +
      options.map((o) => `<option value="${o.value}">${escapeHtml(o.label)}</option>`).join('');

    copyTargets.innerHTML = options
      .map((o) => `<option value="${o.value}">${escapeHtml(o.label)}</option>`)
      .join('');

    copySourceHint.textContent = '';
    copySubmit.disabled = true;
  }

  // Подсказываем, сколько норм у выбранного источника
  copySource?.addEventListener('change', () => {
    const id = Number(copySource.value);
    if (!id) {
      copySourceHint.textContent = '';
      copySubmit.disabled = true;
      return;
    }

    const count = normsCountByPosition().get(id) ?? 0;
    copySourceHint.textContent = count
      ? `У этой должности ${count} норм(а)`
      : 'У этой должности нет норм — копировать нечего';
    copySubmit.disabled = count === 0;

    // Источник не должен быть получателем — убираем его из списка
    Array.from(copyTargets.options).forEach((opt) => {
      opt.disabled = Number(opt.value) === id;
      if (opt.disabled) opt.selected = false;
    });
  });

  document.getElementById('btn-copy-norms')?.addEventListener('click', async () => {
    // Свежие данные: нормы могли измениться. Без paginated эндпоинт отдаёт
    // обычный массив, поэтому проверяем тип явно
    try {
      const data = await API.get('/api/v1/position_ppe_norms');
      allNorms = Array.isArray(data) ? data : (data.items ?? []);
    } catch (err) {
      window.showToast(`Ошибка загрузки норм: ${err.message}`, 'danger');
      return;
    }
    fillCopySelects();
    bootstrap.Modal.getOrCreateInstance(copyModalEl).show();
  });

  copySubmit?.addEventListener('click', async () => {
    const sourceId = Number(copySource.value);
    const targetIds = Array.from(copyTargets.selectedOptions).map((o) => Number(o.value));

    if (!sourceId) {
      window.showToast('Выберите должность-источник', 'danger');
      return;
    }
    if (!targetIds.length) {
      window.showToast('Выберите хотя бы одну должность-получателя', 'danger');
      return;
    }

    copySubmit.disabled = true;
    try {
      const res = await API.post('/api/v1/position_ppe_norms/copy', {
        source_position_id: sourceId,
        target_position_ids: targetIds,
      });
      window.showToast(res.message, 'success');
      bootstrap.Modal.getOrCreateInstance(copyModalEl).hide();
      loadPage(1);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      copySubmit.disabled = false;
    }
  });

  // --- Пункты норм: только чтение справочника для выпадающего списка -----
  async function loadTypicalNorms() {
    allTypicalNorms = await API.get('/api/v1/typical_norms');
    fillTypicalNormSelect();
  }

  function fillTypicalNormSelect() {
    if (!modalTypicalNorm) return;

    // Выбранное значение не теряем: список перерисовывается при каждой загрузке
    const current = modalTypicalNorm.value;
    modalTypicalNorm.innerHTML = '<option value="">Не указан</option>' +
      allTypicalNorms.map((n) => {
        const tail = n.description.length > 60 ? `${n.description.slice(0, 60)}…` : n.description;
        return `<option value="${n.id}">${escapeHtml(n.clause)} — ${escapeHtml(tail)}</option>`;
      }).join('');

    if (current) modalTypicalNorm.value = current;
  }

  WS.subscribe((data) => {
    if (data.event === 'norm_updated') loadData();
    // Справочник пунктов норм правят на соседней вкладке: в выпадающем списке
    // формы остались бы старые пункты
    if (data.event === 'typical_norm_updated') loadTypicalNorms();
  });

  // Срок носки и количество — только цифры, не больше трёх: «1,5» в поле
  // срока давало неверную дату окончания носки
  FormHelper.onlyDigits(createForm?.elements['wear_period_value'], 3);
  FormHelper.onlyDigits(createForm?.elements['quantity'], 3);

  loadData();
})();

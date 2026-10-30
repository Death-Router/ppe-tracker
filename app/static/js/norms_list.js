(() => {
  const posSelect = document.getElementById('position-select');
  const normsContainer = document.getElementById('norms-container');
  const tbody = document.querySelector('#norms-table tbody');
  const createForm = document.getElementById('create-norm-form');
  const itemSelect = document.getElementById('norm-item-input'); // datalist input
  const itemIdInput = document.getElementById('norm-item-id');
  const itemsDatalist = document.getElementById('ppe-items-list');
  const modalElement = document.getElementById('createNormModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = createForm.querySelector('button[type="submit"]');

  let allPpeItems = [];
  let currentPositionId = null;
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
    if (unit === 'день') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} дней`;
      if (lastDigit === 1) return `${num} день`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} дня`;
      return `${num} дней`;
    }
    if (unit === 'смена') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} смен`;
      if (lastDigit === 1) return `${num} смена`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} смены`;
      return `${num} смен`;
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
    if (shortName.toLowerCase() === 'комплект') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} комплектов`;
      if (lastDigit === 1) return `${num} комплект`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} комплекта`;
      return `${num} комплектов`;
    }
    return `${num} ${shortName}`;
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function init() {
    try {
      const positions = await API.get('/api/v1/positions');
      posSelect.innerHTML = '<option value="">-- Выберите должность --</option>' + 
        positions.map(p => `<option value="${p.id}">${p.department?.name ?? ''} / ${p.name}</option>`).join('');

      allPpeItems = await API.get('/api/v1/ppe_items');
      
      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name} (${i.function?.name ?? ''} / ${i.size_group?.name ?? ''})" data-id="${i.id}"></option>`
      ).join('');
    } catch (err) {
      window.showToast(`Ошибка инициализации: ${err.message}`, 'danger');
    }
  }

  async function loadNorms(positionId) {
    if (!positionId) {
      normsContainer.classList.add('d-none');
      return;
    }
    
    currentPositionId = Number(positionId);
    normsContainer.classList.remove('d-none');
    tbody.innerHTML = '<tr><td colspan="4" class="text-center text-muted py-3">Загрузка...</td></tr>';

    try {
      const allNorms = await API.get('/api/v1/position_ppe_norms');
      const filtered = allNorms.filter(n => n.position_id === currentPositionId);
      renderTable(filtered);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-3">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(norms) {
    if (!norms.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-3">Норм пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = norms.map(n => {
      const periodStr = formatPeriod(n.wear_period_value, n.wear_period_unit);
      const qtyStr = formatUnit(n.quantity, n.ppe_item?.unit?.short_name);
      return `
      <tr data-norm-id="${n.id}">
        <td><strong>${escapeHtml(n.ppe_item?.name ?? '—')}</strong></td>
        <td>${periodStr}</td>
        <td>${qtyStr}</td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editNorm(${n.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteNorm(${n.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  posSelect.addEventListener('change', (e) => loadNorms(e.target.value));

  // Обработчик ввода в поле СИЗ (поиск по datalist)
  itemSelect.addEventListener('input', (e) => {
    const val = e.target.value;
    const option = Array.from(itemsDatalist.options).find(opt => opt.value === val);
    if (option) {
      itemIdInput.value = option.getAttribute('data-id');
    } else {
      itemIdInput.value = '';
    }
  });

  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    itemSelect.value = '';
    itemIdInput.value = '';
  };

  window.editNorm = async (normId) => {
    try {
      const norm = await API.get(`/api/v1/position_ppe_norms/${normId}`);
      editingNormId = normId;
      modalTitle.textContent = 'Редактирование нормы';
      submitBtn.textContent = 'Сохранить';

      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);
      if (item) {
        itemSelect.value = `${item.name} (${item.function?.name ?? ''} / ${item.size_group?.name ?? ''})`;
        itemIdInput.value = item.id;
      }
      createForm.elements['wear_period_value'].value = norm.wear_period_value;
      createForm.elements['wear_period_unit'].value = norm.wear_period_unit;
      createForm.elements['quantity'].value = norm.quantity;

      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка загрузки нормы: ${err.message}`, 'danger');
    }
  };

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!currentPositionId) return;

    const payload = {
      position_id: currentPositionId,
      ppe_item_id: Number(itemIdInput.value),
      wear_period_value: createForm.elements['wear_period_value'].value.trim(),
      wear_period_unit: createForm.elements['wear_period_unit'].value,
      quantity: createForm.elements['quantity'].value.trim()
    };

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
      loadNorms(currentPositionId);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteNorm = async (id) => {
    if (!confirm('Удалить эту норму?')) return;
    try {
      await API.request(`/api/v1/position_ppe_norms/${id}`, { method: 'DELETE' });
      window.showToast('Норма удалена', 'success');
      loadNorms(currentPositionId);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.querySelector('button[data-bs-target="#createNormModal"]')?.addEventListener('click', openCreateModal);

  WS.subscribe((data) => {
    if (data.event === 'norm_updated' && currentPositionId) {
      loadNorms(currentPositionId);
    }
  });

  init();
})();

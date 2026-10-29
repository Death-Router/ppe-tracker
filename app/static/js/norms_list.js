(() => {
  const posSelect = document.getElementById('position-select');
  const normsContainer = document.getElementById('norms-container');
  const tbody = document.querySelector('#norms-table tbody');
  const createForm = document.getElementById('create-norm-form');
  const itemSelect = document.getElementById('norm-item-select');
  const modalElement = document.getElementById('createNormModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = createForm.querySelector('button[type="submit"]');

  let allPpeItems = [];
  let currentPositionId = null;
  let editingNormId = null; // Если редактируем, здесь будет ID

  async function init() {
    try {
      const positions = await API.get('/api/v1/positions');
      posSelect.innerHTML = '<option value="">-- Выберите должность --</option>' + 
        positions.map(p => `<option value="${p.id}">${p.department?.name ?? ''} / ${p.name}</option>`).join('');

      allPpeItems = await API.get('/api/v1/ppe_items');
      
      itemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
        allPpeItems.map(i => `<option value="${i.id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
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

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function formatUnit(value, shortName) {
    if (!shortName) return value;
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${shortName}`;

    // Склонение для "пара"
    if (shortName.toLowerCase() === 'пара') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} пар`;
      if (lastDigit === 1) return `${num} пара`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} пары`;
      return `${num} пар`;
    }
    // Склонение для "штука"
    if (shortName.toLowerCase() === 'штука' || shortName.toLowerCase() === 'шт') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} штук`;
      if (lastDigit === 1) return `${num} штука`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} штуки`;
      return `${num} штук`;
    }
    // Склонение для "комплект"
    if (shortName.toLowerCase() === 'комплект') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} комплектов`;
      if (lastDigit === 1) return `${num} комплект`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} комплекта`;
      return `${num} комплектов`;
    }
    // По умолчанию
    return `${num} ${shortName}`;
  }


  function renderTable(norms) {
    if (!norms.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-3">Норм пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = norms.map(n => `
      <tr data-norm-id="${n.id}">
        <td><strong>${escapeHtml(n.ppe_item?.name ?? '—')}</strong></td>
        <td>${escapeHtml(n.wear_period_value)} ${escapeHtml(n.wear_period_unit)}</td>
        <td>${formatUnit(n.quantity, n.ppe_item?.unit?.short_name)}</td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editNorm(${n.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteNorm(${n.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  posSelect.addEventListener('change', (e) => loadNorms(e.target.value));

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    // Сбрасываем выбранное СИЗ
    if (itemSelect) itemSelect.value = '';
  };

  // Редактирование нормы
  window.editNorm = async (normId) => {
    try {
      // Загружаем данные нормы
      const norm = await API.get(`/api/v1/position_ppe_norms/${normId}`);
      
      editingNormId = normId;
      modalTitle.textContent = 'Редактирование нормы';
      submitBtn.textContent = 'Сохранить';

      // Заполняем форму
      itemSelect.value = norm.ppe_item_id;
      createForm.elements['wear_period_value'].value = norm.wear_period_value;
      createForm.elements['wear_period_unit'].value = norm.wear_period_unit;
      createForm.elements['quantity'].value = norm.quantity;

      // Открываем модалку
      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка загрузки нормы: ${err.message}`, 'danger');
    }
  };

  // Обработка формы (создание или обновление)
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!currentPositionId) return;

    const payload = {
      position_id: currentPositionId,
      ppe_item_id: Number(itemSelect.value),
      wear_period_value: createForm.elements['wear_period_value'].value.trim(),
      wear_period_unit: createForm.elements['wear_period_unit'].value,
      quantity: createForm.elements['quantity'].value.trim()
    };

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingNormId) {
        // Обновление
        payload.version = (await API.get(`/api/v1/position_ppe_norms/${editingNormId}`)).version;
        await API.put(`/api/v1/position_ppe_norms/${editingNormId}`, payload);
        window.showToast('Норма обновлена', 'success');
      } else {
        // Создание
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

  // Привязка кнопки "Добавить норму" к открытию модалки в режиме создания
  document.querySelector('button[data-bs-target="#createNormModal"]')?.addEventListener('click', openCreateModal);

  WS.subscribe((data) => {
    if (data.event === 'norm_updated' && currentPositionId) {
      loadNorms(currentPositionId);
    }
  });

  init();
})();

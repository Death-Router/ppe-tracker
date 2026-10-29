(() => {
  const posSelect = document.getElementById('position-select');
  const normsContainer = document.getElementById('norms-container');
  const tbody = document.querySelector('#norms-table tbody');
  const createForm = document.getElementById('create-norm-form');
  const itemSelect = document.getElementById('norm-item-select');

  let allPpeItems = [];
  let currentPositionId = null;

  // Инициализация: загружаем должности и СИЗ
  async function init() {
    try {
      const positions = await API.get('/api/v1/positions');
      posSelect.innerHTML = '<option value="">-- Выберите должность --</option>' + 
        positions.map(p => `<option value="${p.id}">${p.department?.name ?? ''} / ${p.name}</option>`).join('');

      allPpeItems = await API.get('/api/v1/ppe_items');
      
      // Заполняем выпадающий список СИЗ в модалке
      itemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
        allPpeItems.map(i => `<option value="${i.id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
    } catch (err) {
      window.showToast(`Ошибка инициализации: ${err.message}`, 'danger');
    }
  }

  // Загрузка норм для выбранной должности
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

  function formatPeriod(value, unit) {
    if (!value) return '—';
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${unit}`;

    // Склонение для "год"
    if (unit === 'год') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} лет`;
      if (lastDigit === 1) return `${num} год`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} года`;
      return `${num} лет`;
    }
    // Склонение для "месяц"
    if (unit === 'месяц') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} месяцев`;
      if (lastDigit === 1) return `${num} месяц`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} месяца`;
      return `${num} месяцев`;
    }
    // Склонение для "день"
    if (unit === 'день') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} дней`;
      if (lastDigit === 1) return `${num} день`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} дня`;
      return `${num} дней`;
    }
    // Склонение для "смена"
    if (unit === 'смена') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} смен`;
      if (lastDigit === 1) return `${num} смена`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} смены`;
      return `${num} смен`;
    }
    // Для "до износа" и других — просто возвращаем как есть
    return `${value} ${unit}`;
  }


  function renderTable(norms) {
    if (!norms.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-3">Норм пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = norms.map(n => `
      <tr data-norm-id="${n.id}">
        <td><strong>${escapeHtml(n.ppe_item?.name ?? '—')}</strong></td>
        <td>${formatPeriod(n.wear_period_value, n.wear_period_unit)}</td>
        <td>${escapeHtml(n.quantity)}</td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-danger" onclick="deleteNorm(${n.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  posSelect.addEventListener('change', (e) => loadNorms(e.target.value));

  // Обработка формы добавления нормы
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
      await API.post('/api/v1/position_ppe_norms/', payload);
      window.showToast('Норма добавлена', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createNormModal')).hide();
      createForm.reset();
      loadNorms(currentPositionId);
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
      loadNorms(currentPositionId);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'norm_updated' && currentPositionId) {
      loadNorms(currentPositionId);
    }
  });

  init();
})();

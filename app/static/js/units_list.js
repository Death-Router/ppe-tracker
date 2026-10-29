(() => {
  const tbody = document.querySelector('#units-table tbody');
  const createForm = document.getElementById('create-form');
  const modalTitle = document.getElementById('unit-modal-title');
  const unitIdInput = document.getElementById('unit-id');

  async function loadUnits() {
    try {
      const units = await API.get('/api/v1/units');
      renderTable(units);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(units) {
    if (!units.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Единиц измерения пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = units.map(u => `
      <tr data-unit-id="${u.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(u.name)}</strong></td>
        <td class="py-1">${escapeHtml(u.short_name)}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editUnit(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUnit(${u.id}, '${escapeHtml(u.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    unitIdInput.value = '';
    modalTitle.textContent = 'Новая единица измерения';
    createForm.reset();
  };

  // Редактирование
  window.editUnit = async (id) => {
    try {
      const unit = await API.get(`/api/v1/units`); // Получаем все, чтобы найти нужную
      const found = unit.find(u => u.id === id);
      if (!found) throw new Error('Единица не найдена');
      
      unitIdInput.value = id;
      modalTitle.textContent = 'Редактирование единицы';
      createForm.elements['name'].value = found.name;
      createForm.elements['short_name'].value = found.short_name;
      
      new bootstrap.Modal(document.getElementById('createModal')).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Сохранение (создание или обновление)
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = unitIdInput.value;
    const payload = FormHelper.serialize(createForm);

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      if (id) {
        await API.put(`/api/v1/units/${id}`, payload);
        window.showToast('Единица обновлена', 'success');
      } else {
        await API.post('/api/v1/units/', payload);
        window.showToast('Единица создана', 'success');
      }
      
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      unitIdInput.value = '';
      loadUnits();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteUnit = async (id, name) => {
    if (!confirm(`Удалить единицу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/units/${id}`, { method: 'DELETE' });
      window.showToast('Единица удалена', 'success');
      loadUnits();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Привязка кнопки "Добавить" к режиму создания
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadUnits();
})();

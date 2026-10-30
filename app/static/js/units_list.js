(() => {
  const tbody = document.querySelector('#units-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement ? modalElement.querySelector('.modal-title') : null;
  const submitBtn = createForm ? createForm.querySelector('button[type="submit"]') : null;

  let editingId = null;

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
    if (!createForm || !modalTitle || !submitBtn) {
      console.warn('Модалка не найдена');
      return;
    }
    editingId = null;
    modalTitle.textContent = 'Новая единица измерения';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    new bootstrap.Modal(modalElement).show();
  };

  // Редактирование
  window.editUnit = async (id) => {
    try {
      const units = await API.get('/api/v1/units');
      const unit = units.find(u => u.id === id);
      if (!unit) throw new Error('Единица не найдена');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование единицы';
      submitBtn.textContent = 'Сохранить';
      
      // Заполняем поля (с проверкой на существование)
      if (createForm.elements['name']) createForm.elements['name'].value = unit.name;
      if (createForm.elements['short_name']) createForm.elements['short_name'].value = unit.short_name;
      
      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  if (createForm) {
    createForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const payload = FormHelper.serialize(createForm);
      const btn = createForm.querySelector('button[type="submit"]');
      if (btn) btn.disabled = true;
      
      try {
        if (editingId) {
          payload.version = (await API.get(`/api/v1/units/${editingId}`)).version;
          await API.put(`/api/v1/units/${editingId}`, payload);
          window.showToast('Единица обновлена', 'success');
        } else {
          await API.post('/api/v1/units/', payload);
          window.showToast('Единица создана', 'success');
        }
        bootstrap.Modal.getInstance(modalElement).hide();
        createForm.reset();
        loadUnits();
      } catch (err) {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      } finally {
        if (btn) btn.disabled = false;
      }
    });
  }

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

  // Привязка кнопки "Добавить" к открытию модалки
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadUnits();
})();

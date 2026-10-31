(() => {
  const tbody = document.querySelector('#units-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement ? modalElement.querySelector('.modal-title') : null;
  const submitBtn = createForm ? createForm.querySelector('button[type="submit"]') : null;

  let editingId = null;

  // Имя/название передаём через data-атрибуты: в onclick строка с кавычкой
  // ломала разметку и позволяла внедрить код (данные приходят из Excel-импорта).
  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('[data-action]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const name = btn.dataset.name || '';
    if (btn.dataset.action === 'delete') window.deleteUnit(id, name);
  });

  async function loadUnits() {
    try {
      const units = await API.get('/api/v1/units');
      renderTable(units);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="state state--error">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(units) {
    if (!units.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="state">Единиц измерения пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = units.map(u => `
      <tr data-unit-id="${u.id}">
        <td><strong>${escapeHtml(u.name)}</strong></td>
        <td>${escapeHtml(u.short_name)}</td>
        <td class="col-actions">
          <button class="btn btn-icon" onclick="editUnit(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${u.id}" data-name="${escapeHtml(u.name)}" title="Удалить"><i class="bi bi-trash"></i></button>
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
    bootstrap.Modal.getOrCreateInstance(modalElement).show();
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
      
      bootstrap.Modal.getOrCreateInstance(modalElement).show();
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
          await API.put(`/api/v1/units/${editingId}`, payload);
          window.showToast('Единица обновлена', 'success');
        } else {
          await API.post('/api/v1/units/', payload);
          window.showToast('Единица создана', 'success');
        }
        bootstrap.Modal.getOrCreateInstance(modalElement).hide();
        createForm.reset();
        loadUnits();
      } catch (err) {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      } finally {
        window.FormValidation.refresh();
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

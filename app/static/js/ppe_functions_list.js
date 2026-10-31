(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;
  let editingVersion = null;

  // Имя/название передаём через data-атрибуты: в onclick строка с кавычкой
  // ломала разметку и позволяла внедрить код (данные приходят из Excel-импорта).
  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('[data-action]');
    if (!btn) return;
    const id = Number(btn.dataset.id);
    const name = btn.dataset.name || '';
    if (btn.dataset.action === 'delete') window.deleteFunction(id, name);
  });

  async function loadFunctions() {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      renderTable(funcs);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="state state--error">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(funcs) {
    if (!funcs.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="state">Функций пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = funcs.map(f => `
      <tr data-id="${f.id}">
        <td><strong>${escapeHtml(f.name)}</strong></td>
        <td class="col-actions">
          <button class="btn btn-icon" onclick="editFunction(${f.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${f.id}" data-name="${escapeHtml(f.name)}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingId = null;
    editingVersion = null;
    modalTitle.textContent = 'Новая функция';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    bootstrap.Modal.getOrCreateInstance(modalElement).show();
  };

  // Редактирование
  window.editFunction = async (id) => {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      const func = funcs.find(f => f.id === id);
      if (!func) throw new Error('Функция не найдена');
      
      editingId = id;
      editingVersion = func.version ?? null;
      modalTitle.textContent = 'Редактирование функции';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = func.name;
      
      bootstrap.Modal.getOrCreateInstance(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        payload.version = editingVersion;
        await API.put(`/api/v1/ppe_functions/${editingId}`, payload);
        window.showToast('Функция обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_functions/', payload);
        window.showToast('Функция создана', 'success');
      }
      bootstrap.Modal.getOrCreateInstance(modalElement).hide();
      createForm.reset();
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

  window.deleteFunction = async (id, name) => {
    if (!confirm(`Удалить функцию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_functions/${id}`, { method: 'DELETE' });
      window.showToast('Функция удалена', 'success');
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Привязка кнопки "Добавить" к открытию модалки
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadFunctions();
})();

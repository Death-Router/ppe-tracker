(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;

  async function loadFunctions() {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      renderTable(funcs);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="state state--error">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

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
          <button class="btn btn-icon btn-icon--danger" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новая функция';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    new bootstrap.Modal(modalElement).show();
  };

  // Редактирование
  window.editFunction = async (id) => {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      const func = funcs.find(f => f.id === id);
      if (!func) throw new Error('Функция не найдена');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование функции';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = func.name;
      
      new bootstrap.Modal(modalElement).show();
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
        payload.version = (await API.get(`/api/v1/ppe_functions/${editingId}`)).version;
        await API.put(`/api/v1/ppe_functions/${editingId}`, payload);
        window.showToast('Функция обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_functions/', payload);
        window.showToast('Функция создана', 'success');
      }
      bootstrap.Modal.getInstance(modalElement).hide();
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

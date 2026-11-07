(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;
  let editingVersion = null;

  onRowAction(tbody, {
    delete: (id, name) => window.deleteFunction(id, name),
  });

  async function loadFunctions() {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      renderTable(funcs);
    } catch (err) {
      tableState(tbody, 2, `Ошибка: ${err.message}`, { error: true });
    }
  }

  function renderTable(funcs) {
    if (!funcs.length) {
      tableState(tbody, 2, 'Функций пока нет');
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
    ModalHelper.setTitle(modalElement, 'Новая функция');
    submitBtn.textContent = 'Создать';
    createForm.reset();
    ModalHelper.show(modalElement);
  };

  // Редактирование
  window.editFunction = async (id) => {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      const func = funcs.find(f => f.id === id);
      if (!func) throw new Error('Функция не найдена');
      
      editingId = id;
      editingVersion = func.version ?? null;
      ModalHelper.setTitle(modalElement, 'Редактирование функции');
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = func.name;
      
      ModalHelper.show(modalElement);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    await FormHelper.send(createForm, async (payload) => {
      if (editingId) {
        payload.version = editingVersion;
        await API.put(`/api/v1/ppe_functions/${editingId}`, payload);
        window.showToast('Функция обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_functions/', payload);
        window.showToast('Функция создана', 'success');
      }
    }, {
      onSuccess: () => {
        ModalHelper.hide(modalElement);
        createForm.reset();
        loadFunctions();
      },
    });
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
  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  // Справочник мог изменить другой пользователь — перечитываем список
  WS.subscribe((data) => {
    if (data.event === 'function_updated') loadFunctions();
  });

  loadFunctions();
})();

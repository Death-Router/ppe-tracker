(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  // Элементы модалки размеров
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeGroupName = document.getElementById('size-group-name');
  const sizeGroupIdInput = document.getElementById('size-group-id');

  let editingId = null;
  let editingVersion = null;

  onRowAction(tbody, {
    delete: (id, name) => window.deleteGroup(id, name),
    sizes: (id, name) => window.openSizesModal(id, name),
  });

  async function loadGroups() {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      renderTable(groups);
    } catch (err) {
      tableState(tbody, 3, `Ошибка: ${err.message}`, { error: true });
    }
  }

  function renderTable(groups) {
    if (!groups.length) {
      tableState(tbody, 3, 'Групп пока нет');
      return;
    }
    tbody.innerHTML = groups.map(g => `
      <tr data-id="${g.id}">
        <td><strong>${escapeHtml(g.name)}</strong></td>
        <td class="cell-muted">${g.description ? escapeHtml(g.description) : '—'}</td>
        <td class="py-1 text-end text-nowrap">
          <button class="btn btn-icon me-1" data-action="sizes" data-id="${g.id}" data-name="${escapeHtml(g.name)}" title="Размеры"><i class="bi bi-rulers"></i></button>
          <button class="btn btn-icon me-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${g.id}" data-name="${escapeHtml(g.name)}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания/редактирования группы
  window.openCreateModal = () => {
    editingId = null;
    editingVersion = null;
    modalTitle.textContent = 'Новая размерная группа';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    bootstrap.Modal.getOrCreateInstance(modalElement).show();
  };

  window.editGroup = async (id) => {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      const group = groups.find(g => g.id === id);
      if (!group) throw new Error('Группа не найдена');
      
      editingId = id;
      editingVersion = group.version ?? null;
      modalTitle.textContent = 'Редактирование группы';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = group.name;
      createForm.elements['description'].value = group.description ?? '';
      
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
        await API.put(`/api/v1/ppe_size_groups/${editingId}`, payload);
        window.showToast('Группа обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_size_groups/', payload);
        window.showToast('Группа создана', 'success');
      }
      bootstrap.Modal.getOrCreateInstance(modalElement).hide();
      createForm.reset();
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

  window.deleteGroup = async (id, name) => {
    if (!confirm(`Удалить группу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_size_groups/${id}`, { method: 'DELETE' });
      window.showToast('Группа удалена', 'success');
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // --- Управление размерами ---
  window.openSizesModal = async (groupId, groupName) => {
    sizeGroupIdInput.value = groupId;
    sizeGroupName.textContent = groupName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = bootstrap.Modal.getOrCreateInstance(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
      renderSizesList(sizes);
    } catch (err) {
      sizesList.innerHTML = `<li class="list-group-item text-danger">Ошибка: ${err.message}</li>`;
    }
  };

  function renderSizesList(sizes) {
    if (!sizes.length) {
      sizesList.innerHTML = '<li class="list-group-item text-muted">Нет добавленных размеров</li>';
      return;
    }
    sizesList.innerHTML = sizes.map(s => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
      <li class="list-group-item d-flex justify-content-between align-items-center py-1">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-icon btn-icon--danger" onclick="deleteSize(${s.id})" title="Удалить размер" aria-label="Удалить размер">✕</button>
      </li>
    `}).join('');
  }

  sizeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const groupId = Number(sizeGroupIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { size_group_id: groupId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  window.deleteSize = async (sizeId) => {
    if (!confirm('Удалить этот размер?')) return;
    try {
      await API.request(`/api/v1/ppe_sizes/${sizeId}`, { method: 'DELETE' });
      window.showToast('Размер удален', 'success');
      const groupId = Number(sizeGroupIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  // Открытую модалку размеров перерисовываем только для её группы: иначе
  // добавленный в другой группе размер подменял бы список на экране
  async function reloadSizesIfOpen(sizeGroupId) {
    if (!sizesModalElement?.classList.contains('show')) return;

    const openedGroup = Number(sizeGroupIdInput.value);
    if (sizeGroupId != null && Number(sizeGroupId) !== openedGroup) return;

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${openedGroup}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  }

  WS.subscribe((data) => {
    if (data.event === 'size_group_updated') loadGroups();
    if (data.event === 'size_updated') reloadSizesIfOpen(data.size_group_id);
  });

  loadGroups();
})();

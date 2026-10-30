(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;

  async function loadGroups() {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      renderTable(groups);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(groups) {
    if (!groups.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Групп пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = groups.map(g => `
      <tr data-id="${g.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(g.name)}</strong></td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новая размерная группа';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    new bootstrap.Modal(modalElement).show();
  };

  window.editGroup = async (id) => {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      const group = groups.find(g => g.id === id);
      if (!group) throw new Error('Группа не найдена');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование группы';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = group.name;
      
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
        payload.version = (await API.get(`/api/v1/ppe_size_groups/${editingId}`)).version;
        await API.put(`/api/v1/ppe_size_groups/${editingId}`, payload);
        window.showToast('Группа обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_size_groups/', payload);
        window.showToast('Группа создана', 'success');
      }
      bootstrap.Modal.getInstance(modalElement).hide();
      createForm.reset();
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
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

  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadGroups();
})();

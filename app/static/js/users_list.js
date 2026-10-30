(() => {
  const tbody = document.querySelector('#users-table tbody');
  const form = document.getElementById('user-form');
  const modalTitle = document.getElementById('modal-title');
  const userIdInput = document.getElementById('user-id');
  const passwordInput = document.getElementById('password');
  const passwordHint = document.getElementById('password-hint');
  const roleSelect = document.getElementById('role-select');
  const departmentSelect = document.getElementById('department-select');
  const departmentGroup = document.getElementById('department-group');
  const subdepGroup = document.getElementById('subdep-group');
  const includeSubdep = document.getElementById('include-subdep');

  let allUsers = [];
  let allDepartments = [];
  let editingId = null;

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadData() {
    try {
      allUsers = await API.get('/api/v1/users');
      allDepartments = await API.get('/api/v1/departments');
      renderTable(allUsers);
      
      // Заполняем выпадающий список подразделений
      const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
      departmentSelect.innerHTML = '<option value="">Не указано</option>' +
        sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(users) {
    if (!users.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-4">Пользователей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = users.map(u => {
      const deptName = allDepartments.find(d => d.id === u.department_id)?.name || '—';
      const roleName = u.role === 'admin' ? 'Администратор' : 'Специалист ОТ';
      return `
      <tr data-user-id="${u.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(u.username)}</strong></td>
        <td class="py-1"><span class="badge bg-purple">${roleName}</span></td>
        <td class="py-1">${escapeHtml(deptName)}</td>
        <td class="py-1">${u.is_active ? '<span class="badge bg-success">Да</span>' : '<span class="badge bg-danger">Нет</span>'}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editUser(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUser(${u.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новый пользователь';
    userIdInput.value = '';
    form.reset();
    passwordInput.required = true;
    passwordHint.style.display = 'none';
    new bootstrap.Modal(document.getElementById('createModal')).show();
  };

  // Редактирование
  window.editUser = async (id) => {
    try {
      const user = allUsers.find(u => u.id === id);
      if (!user) throw new Error('Пользователь не найден');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование пользователя';
      userIdInput.value = id;
      
      form.elements['username'].value = user.username;
      passwordInput.value = '';
      passwordInput.required = false;
      passwordHint.style.display = 'block';
      
      roleSelect.value = user.role;
      departmentSelect.value = user.department_id || '';
      includeSubdep.checked = user.include_subdepartments || false;
      form.elements['is_active'].checked = user.is_active;
      
      new bootstrap.Modal(document.getElementById('createModal')).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Сохранение
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(form);
    
    if (payload.department_id) {
      payload.department_id = Number(payload.department_id);
    } else {
      payload.department_id = null;
    }
    
    payload.include_subdepartments = includeSubdep.checked;
    payload.is_active = form.elements['is_active'].checked;
    
    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        if (!payload.password) delete payload.password;
        await API.put(`/api/v1/users/${editingId}`, payload);
        window.showToast('Пользователь обновлен', 'success');
      } else {
        await API.post('/api/v1/users/', payload);
        window.showToast('Пользователь создан', 'success');
      }
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // Удаление
  window.deleteUser = async (id) => {
    if (!confirm('Удалить этого пользователя?')) return;
    try {
      await API.request(`/api/v1/users/${id}`, { method: 'DELETE' });
      window.showToast('Пользователь удален', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Привязка кнопки "Добавить"
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadData();
})();

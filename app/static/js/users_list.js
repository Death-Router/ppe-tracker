(() => {
  const tbody = document.querySelector('#users-table tbody');
  const form = document.getElementById('user-form');
  // Модалку берём от самой формы, а не по id: одна и та же разметка живёт
  // на двух страницах с разными id (#createModal на /users,
  // #createUserModal на /settings). Жёсткий селектор `#createModal` на
  // настройках давал null и ошибку «Cannot set properties of null» при
  // открытии и редактировании пользователя.
  const modalElement = form?.closest('.modal') || document.getElementById('createModal');
  const modalTitle = modalElement?.querySelector('.modal-title') || null;
  const userIdInput = document.getElementById('user-id');
  const passwordInput = document.getElementById('password');
  const passwordHint = document.getElementById('password-hint');
  const roleSelect = document.getElementById('role-select');
  const departmentSelect = document.getElementById('department-select');
  const departmentGroup = document.getElementById('department-group');
  const subdepGroup = document.getElementById('subdep-group');
  const includeSubdep = document.getElementById('include-subdep');

  // Если на странице нет таблицы пользователей, просто выходим
  if (!tbody) return;

  function showModal() {
    if (modalElement) bootstrap.Modal.getOrCreateInstance(modalElement).show();
  }

  function hideModal() {
    if (modalElement) bootstrap.Modal.getOrCreateInstance(modalElement).hide();
  }

  function setModalTitle(text) {
    if (modalTitle) modalTitle.textContent = text;
  }

  let allUsers = [];
  let allDepartments = [];
  let editingId = null;


  async function loadData() {
    try {
      allUsers = await API.get('/api/v1/users');
      allDepartments = await API.get('/api/v1/departments');
      renderTable(allUsers);
      
      const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
      if (departmentSelect) {
        departmentSelect.innerHTML = '<option value="">Не указано</option>' +
          sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="state state--error">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(users) {
    if (!users.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="state">Пользователей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = users.map(u => {
      const deptName = allDepartments.find(d => d.id === u.department_id)?.name || '—';
      const roleName = u.role === 'admin' ? 'Администратор' : 'Специалист ОТ';
      return `
      <tr data-user-id="${u.id}">
        <td><strong>${escapeHtml(u.username)}</strong></td>
        <td><span class="badge-soft badge-purple">${roleName}</span></td>
        <td>${escapeHtml(deptName)}</td>
        <td>${u.is_active ? '<span class="badge-soft badge-purple">Да</span>' : '<span class="badge-soft badge-orange">Нет</span>'}</td>
        <td class="col-actions">
          <button class="btn btn-icon" onclick="editUser(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" onclick="deleteUser(${u.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  window.openCreateModal = () => {
    editingId = null;
    setModalTitle('Новый пользователь');
    userIdInput.value = '';
    form.reset();
    passwordInput.required = true;
    passwordHint.classList.add('d-none');
    window.FormValidation.refresh(form);
    showModal();
  };

  window.editUser = async (id) => {
    try {
      const user = allUsers.find(u => u.id === id);
      if (!user) throw new Error('Пользователь не найден');
      
      editingId = id;
      setModalTitle('Редактирование пользователя');
      userIdInput.value = id;
      
      form.elements['username'].value = user.username;
      passwordInput.value = '';
      passwordInput.required = false;
      passwordHint.classList.remove('d-none');
      
      roleSelect.value = user.role;
      departmentSelect.value = user.department_id || '';
      includeSubdep.checked = user.include_subdepartments || false;
      window.FormValidation.refresh(form);
      form.elements['is_active'].checked = user.is_active;
      
      showModal();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

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
      hideModal();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

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

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  // Пользователей и подразделения в списке могли поменять в другой вкладке
  WS.subscribe((data) => {
    if (data.event === 'user_updated') loadData();
  });

  loadData();
})();

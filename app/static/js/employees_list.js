(() => {
  const tbody = document.querySelector('#employees-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');
  const createPosSelect = document.getElementById('create-pos');

  async function loadEmployees() {
    try {
      const employees = await API.get('/api/v1/employees');
      renderTable(employees);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) {
    return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  }

  function renderTable(employees) {
    if (!employees.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-4">Сотрудников пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = employees.map(e => {
      const fio = `${e.last_name} ${e.first_name} ${e.middle_name ?? ''}`.trim();
      return `
      <tr data-employee-id="${e.id}">
        <td>${e.id}</td>
        <td>${escapeHtml(fio)}</td>
        <td>${escapeHtml(e.personnel_number)}</td>
        <td>${escapeHtml(e.position_rel?.name ?? '—')}</td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/employees/${e.id}/edit">Ред.</a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteEmployee(${e.id}, '${escapeHtml(fio)}')">Удалить</button>
        </td>
      </tr>
      `;
    }).join('');
  }

  async function loadDepartmentsForSelect() {
    try {
      const depts = await API.get('/api/v1/departments');
      createDeptSelect.innerHTML = '<option value="">Выберите подразделение...</option>' +
        depts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
    } catch (err) {
      createDeptSelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  async function loadPositionsForSelect(deptId) {
    if (!deptId) {
      createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
      return;
    }
    try {
      const positions = await API.get('/api/v1/positions');
      const filtered = positions.filter(p => p.department_id === Number(deptId));
      createPosSelect.innerHTML = '<option value="">Выберите должность...</option>' +
        filtered.map(p => `<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('');
    } catch (err) {
      createPosSelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  // Обработчик смены подразделения в модалке
  createDeptSelect.addEventListener('change', (e) => {
    loadPositionsForSelect(e.target.value);
  });

  // Создание сотрудника
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.department_id = Number(payload.department_id);
    payload.position_id = Number(payload.position_id);
    payload.ppe_sizes = []; // Обязательно для EmployeeCreate

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/employees/', payload);
      window.showToast('Сотрудник создан', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
      loadEmployees();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // Удаление
  window.deleteEmployee = async (id, fio) => {
    if (!confirm(`Удалить сотрудника "${fio}"?`)) return;
    try {
      await API.request(`/api/v1/employees/${id}`, { method: 'DELETE' });
      window.showToast('Сотрудник удален', 'success');
      loadEmployees();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'employee_updated' || data.event === 'employee_created') {
      setTimeout(loadEmployees, 300);
    }
  });

  loadDepartmentsForSelect();
  loadEmployees();
})();

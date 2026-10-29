(() => {
  const employeeId = window.EMPLOYEE_ID;
  const form = document.getElementById('employee-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const deptSelect = document.getElementById('department_id');
  const posSelect = document.getElementById('position_id');
  
  const sizesTableBody = document.querySelector('#sizes-table tbody');
  const addSizeBtn = document.getElementById('add-size-btn');

  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  let allPpeItems = [];

  // Загрузка справочников
  async function loadDepartments() {
    const depts = await API.get('/api/v1/departments');
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      depts.map(d => `<option value="${d.id}">${d.name}</option>`).join('');
  }

  async function loadPositions(deptId, selectedId = null) {
    if (!deptId) {
      posSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
      return;
    }
    const positions = await API.get('/api/v1/positions');
    const filtered = positions.filter(p => p.department_id === Number(deptId));
    posSelect.innerHTML = '<option value="">Выберите...</option>' + 
      filtered.map(p => `<option value="${p.id}" ${p.id === selectedId ? 'selected' : ''}>${p.name}</option>`).join('');
  }

  async function loadPpeItems() {
    allPpeItems = await API.get('/api/v1/ppe_items');
  }

  deptSelect.addEventListener('change', (e) => {
    loadPositions(e.target.value);
  });

  // Управление таблицей размеров
  function createSizeRow(itemId = '', sizeValue = '') {
    const tr = document.createElement('tr');
    const options = allPpeItems.map(item => 
      `<option value="${item.id}" ${item.id === itemId ? 'selected' : ''}>${item.name} (${item.category?.name ?? ''})</option>`
    ).join('');
    
    tr.innerHTML = `
      <td>
        <select class="form-select form-select-sm ppe-item-select" required>
          <option value="">Выберите СИЗ...</option>
          ${options}
        </select>
      </td>
      <td>
        <input type="text" class="form-control form-control-sm size-value-input" value="${sizeValue}" placeholder="Например, 42" required maxlength="50">
      </td>
      <td class="text-center">
        <button type="button" class="btn btn-sm btn-outline-danger remove-size-btn">✕</button>
      </td>
    `;
    
    tr.querySelector('.remove-size-btn').addEventListener('click', () => {
      tr.remove();
      isDirty = true;
    });

    return tr;
  }

  addSizeBtn.addEventListener('click', () => {
    sizesTableBody.appendChild(createSizeRow());
    isDirty = true;
  });

  // Загрузка сотрудника
  async function loadEmployee(isWsUpdate = false) {
    try {
      const emp = await API.get(`/api/v1/employees/${employeeId}`);
      
      if (isWsUpdate && isDirty) {
        window.showToast('Сотрудник изменён другим пользователем.', 'warning');
        versionInput.value = emp.version ?? '';
        return;
      }

      // Обновленный список полей, включая новые
      const FIELDS = [
        'personnel_number', 'last_name', 'first_name', 'middle_name',
        'hire_date', 'position_change_date', 'gender', 'height'
      ];
      
      for (const f of FIELDS) {
        if (form.elements[f]) {
          // Для дат нужно привести к формату YYYY-MM-DD
          if (f.includes('_date') && emp[f]) {
             form.elements[f].value = emp[f].split('T')[0];
          } else {
             form.elements[f].value = emp[f] ?? '';
          }
        }
      }
      
      deptSelect.value = emp.department_id ?? '';
      await loadPositions(emp.department_id, emp.position_id);

      // Отрисовка размеров
      sizesTableBody.innerHTML = '';
      if (emp.ppe_sizes && emp.ppe_sizes.length > 0) {
        emp.ppe_sizes.forEach(size => {
          sizesTableBody.appendChild(createSizeRow(size.ppe_item_id, size.size_value));
        });
      }

      versionInput.value = emp.version ?? '';
      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');

    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // Сохранение
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;
    
    const ppeSizes = [];
    const rows = sizesTableBody.querySelectorAll('tr');
    let hasErrors = false;

    rows.forEach(tr => {
      const select = tr.querySelector('.ppe-item-select');
      const sizeInput = tr.querySelector('.size-value-input');
      
      const itemId = Number(select.value);
      const sizeVal = sizeInput.value.trim();

      if (!itemId || !sizeVal) {
        hasErrors = true;
        select.classList.add('is-invalid');
        sizeInput.classList.add('is-invalid');
      } else {
        ppeSizes.push({ ppe_item_id: itemId, size_value: sizeVal });
      }
    });

    if (hasErrors) {
      window.showToast('Заполните все поля в таблице размеров', 'danger');
      btnSubmit.disabled = false;
      return;
    }

    const payload = FormHelper.serialize(form);
    // Приводим ID к числам
    payload.department_id = Number(payload.department_id);
    payload.position_id = Number(payload.position_id);
    
    // Обработка пустых дат (чтобы Pydantic не ругался)
    if (!payload.hire_date) payload.hire_date = null;
    if (!payload.position_change_date) payload.position_change_date = null;

    payload.ppe_sizes = ppeSizes;

    try {
      const updated = await API.put(`/api/v1/employees/${employeeId}`, payload);
      if (updated?.version != null) versionInput.value = updated.version;
      isDirty = false;
      window.showToast('Изменения сохранены', 'success');
    } catch (err) {
      if (err.isConflict) {
        conflictAlert.classList.remove('d-none');
        conflictAlert.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } else {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      }
    } finally {
      btnSubmit.disabled = false;
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'employee_updated' && data.employee_id === employeeId) {
      loadEmployee(true);
    }
  });

  // Инициализация
  Promise.all([loadDepartments(), loadPpeItems()]).then(() => loadEmployee());
})();

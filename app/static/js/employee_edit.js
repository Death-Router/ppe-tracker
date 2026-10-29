(() => {
  console.log('🚀 employee_edit.js загружен (с выбором размеров)');
  
  const employeeId = window.EMPLOYEE_ID;
  const form = document.getElementById('employee-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const deptSelect = document.getElementById('department_id');
  const posSelect = document.getElementById('position_id');
  const genderSelect = document.getElementById('gender');
  
  const sizesTableBody = document.querySelector('#sizes-table tbody');
  const addSizeBtn = document.getElementById('add-size-btn');

  const issueForm = document.getElementById('issue-form');
  const issuesTableBody = document.querySelector('#issues-table tbody');
  
  let allPpeItems = [];
  let allSizesCache = {}; // Кэш размеров: {ppe_item_id: [sizes]}
  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  // --- Загрузка справочников ---
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

  async function loadAllPpeItems() {
    allPpeItems = await API.get('/api/v1/ppe_items');
  }

  // --- Загрузка размеров для конкретного СИЗ ---
  async function getSizesForItem(itemId) {
    if (allSizesCache[itemId]) {
      return allSizesCache[itemId];
    }
    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      allSizesCache[itemId] = sizes;
      return sizes;
    } catch (err) {
      console.error('Ошибка загрузки размеров:', err);
      return [];
    }
  }

  deptSelect.addEventListener('change', (e) => loadPositions(e.target.value));

  // --- Управление размерами (с выбором из справочника) ---
  async function createSizeRow(itemId = '', sizeValue = '') {
    const tr = document.createElement('tr');
    
    // Получаем текущий пол сотрудника (если выбран)
    const currentGender = genderSelect.value || null;
    
    // Формируем опции для СИЗ
    const options = allPpeItems.map(item => 
      `<option value="${item.id}" ${item.id === itemId ? 'selected' : ''}>${item.name} (${item.category?.name ?? ''})</option>`
    ).join('');
    
    // Получаем размеры для выбранного СИЗ (если itemId передан)
    let sizeOptions = '';
    if (itemId) {
      const sizes = await getSizesForItem(itemId);
      // Фильтруем по полу, если он указан у сотрудника
      let filteredSizes = sizes;
      if (currentGender) {
        filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
      } else {
        // Если пол не указан, показываем все
        filteredSizes = sizes;
      }
      
      if (filteredSizes.length > 0) {
        sizeOptions = '<option value="">Размер...</option>' + 
          filteredSizes.map(s => {
            const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
            return `<option value="${s.size_value}" ${s.size_value === sizeValue ? 'selected' : ''}>${s.size_value}${genderLabel}</option>`;
          }).join('');
      } else {
        // Если размеров нет, показываем текстовое поле
        sizeOptions = '<option value="">Нет размеров (введите вручную)</option>';
      }
    }

    // Если есть размеры, показываем select, иначе input
    const hasSizes = sizeOptions !== '';
    const sizeInputHtml = hasSizes 
      ? `<select class="form-select form-select-sm size-value-input" required>
           <option value="">Размер...</option>
           ${sizeOptions}
         </select>`
      : `<input type="text" class="form-control form-control-sm size-value-input" value="${sizeValue}" placeholder="Размер" required maxlength="50">`;

    tr.innerHTML = `
      <td>
        <select class="form-select form-select-sm ppe-item-select" required>
          <option value="">Выберите СИЗ...</option>
          ${options}
        </select>
      </td>
      <td>
        ${sizeInputHtml}
      </td>
      <td class="text-center">
        <button type="button" class="btn btn-sm btn-outline-danger remove-size-btn">✕</button>
      </td>
    `;
    
    // Обработчик изменения СИЗ — перерисовываем строку с новыми размерами
    const itemSelect = tr.querySelector('.ppe-item-select');
    itemSelect.addEventListener('change', async () => {
      const newItemId = Number(itemSelect.value);
      if (newItemId) {
        // Получаем размеры для нового СИЗ
        const sizes = await getSizesForItem(newItemId);
        const currentGender = genderSelect.value || null;
        let filteredSizes = sizes;
        if (currentGender) {
          filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
        }
        
        const sizeCell = tr.children[1];
        if (filteredSizes.length > 0) {
          const sizeOptions = '<option value="">Размер...</option>' + 
            filteredSizes.map(s => {
              const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
              return `<option value="${s.size_value}">${s.size_value}${genderLabel}</option>`;
            }).join('');
          sizeCell.innerHTML = `<select class="form-select form-select-sm size-value-input" required>${sizeOptions}</select>`;
        } else {
          sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
        }
      }
    });
    
    tr.querySelector('.remove-size-btn').addEventListener('click', () => {
      tr.remove();
      isDirty = true;
    });
    
    return tr;
  }

  addSizeBtn.addEventListener('click', async () => {
    const tr = await createSizeRow();
    sizesTableBody.appendChild(tr);
    isDirty = true;
  });

  // --- Загрузка сотрудника ---
  async function loadEmployee(isWsUpdate = false) {
    try {
      const emp = await API.get(`/api/v1/employees/${employeeId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Сотрудник изменён другим пользователем.', 'warning');
        versionInput.value = emp.version ?? '';
        return;
      }

      const FIELDS = [
        'personnel_number', 'last_name', 'first_name', 'middle_name',
        'hire_date', 'position_change_date', 'gender', 'height'
      ];
      
      for (const f of FIELDS) {
        if (form.elements[f]) {
          if (f.includes('_date') && emp[f]) {
             form.elements[f].value = emp[f].split('T')[0];
          } else {
             form.elements[f].value = emp[f] ?? '';
          }
        }
      }
      
      deptSelect.value = emp.department_id ?? '';
      await loadPositions(emp.department_id, emp.position_id);

      // Отрисовка размеров (асинхронно)
      sizesTableBody.innerHTML = '';
      if (emp.ppe_sizes && emp.ppe_sizes.length > 0) {
        for (const size of emp.ppe_sizes) {
          const tr = await createSizeRow(size.ppe_item_id, size.size_value);
          sizesTableBody.appendChild(tr);
        }
      }

      versionInput.value = emp.version ?? '';
      isDirty = false;
      loadIssues();
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // --- Выдачи ---
  async function loadIssues() {
    try {
      const issues = await API.get(`/api/v1/employee_ppe_issues/?employee_id=${employeeId}`);
      renderIssuesTable(issues);
    } catch (err) {
      console.error('Ошибка загрузки выдач:', err);
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-2">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderIssuesTable(issues) {
    if (!issues || !issues.length) {
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-2">Нет выданных СИЗ</td></tr>`;
      return;
    }
    issuesTableBody.innerHTML = issues.map(issue => {
      const isExpired = issue.expiry_date && new Date(issue.expiry_date) < new Date();
      const rowClass = isExpired ? 'table-danger' : '';
      const expiryStr = issue.expiry_date ? new Date(issue.expiry_date).toLocaleDateString('ru-RU') : '—';
      return `
        <tr class="${rowClass}">
          <td>${issue.ppe_item?.name ?? '—'}</td>
          <td>${new Date(issue.issue_date).toLocaleDateString('ru-RU')}</td>
          <td>${expiryStr}</td>
          <td>${issue.quantity}</td>
          <td class="text-center"><button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteIssue(${issue.id})">✕</button></td>
        </tr>
      `;
    }).join('');
  }

  // --- Модалка выдачи (прямой fetch) ---
  const issueModalElement = document.getElementById('issueModal');
  if (issueModalElement) {
    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          const select = document.getElementById('issue-item-select');
          if (select) {
            select.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
              data.map(i => `<option value="${i.id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
          }
        })
        .catch(err => console.error('Ошибка загрузки СИЗ:', err));
    });
  }

  if (issueForm) {
    issueForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const payload = FormHelper.serialize(issueForm);
      payload.employee_id = employeeId;
      payload.ppe_item_id = Number(payload.ppe_item_id);
      if (!payload.issue_date) payload.issue_date = new Date().toISOString().split('T')[0];

      const btn = issueForm.querySelector('button[type="submit"]');
      btn.disabled = true;
      try {
        await API.post('/api/v1/employee_ppe_issues/', payload);
        window.showToast('СИЗ выдано', 'success');
        bootstrap.Modal.getInstance(issueModalElement).hide();
        issueForm.reset();
        loadIssues();
      } catch (err) {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      } finally {
        btn.disabled = false;
      }
    });
  }

  window.deleteIssue = async (issueId) => {
    if (!confirm('Удалить запись о выдаче?')) return;
    try {
      await API.request(`/api/v1/employee_ppe_issues/${issueId}`, { method: 'DELETE' });
      window.showToast('Запись удалена', 'success');
      loadIssues();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // --- Сохранение сотрудника ---
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
    payload.department_id = Number(payload.department_id);
    payload.position_id = Number(payload.position_id);
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
    if (data.event === 'employee_updated' && data.employee_id === employeeId) loadEmployee(true);
    if (data.event === 'issue_updated') loadIssues();
  });

  // Инициализация
  loadDepartments()
    .then(loadAllPpeItems)
    .then(() => loadEmployee());
})();

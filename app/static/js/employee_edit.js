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

  const issueForm = document.getElementById('issue-form');
  const issuesTableBody = document.querySelector('#issues-table tbody');
  const normsTableBody = document.querySelector('#norms-table tbody'); // Новая таблица
  
  let allPpeItems = [];
  let allSizesCache = {};
  let currentNorms = []; // Нормы для текущей должности
  let currentIssues = []; // Фактические выдачи
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

  async function getSizesForItem(itemId) {
    if (allSizesCache[itemId]) return allSizesCache[itemId];
    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      allSizesCache[itemId] = sizes;
      return sizes;
    } catch (err) {
      return [];
    }
  }

  deptSelect.addEventListener('change', (e) => loadPositions(e.target.value));

  // --- Размеры ---
  async function createSizeRow(itemId = '', sizeValue = '') {
    const tr = document.createElement('tr');
    const currentGender = form.elements['gender'].value || null;
    
    const options = allPpeItems.map(item => 
      `<option value="${item.id}" ${item.id === itemId ? 'selected' : ''}>${item.name} (${item.category?.name ?? ''})</option>`
    ).join('');
    
    let sizeOptions = '';
    if (itemId) {
      const sizes = await getSizesForItem(itemId);
      let filteredSizes = sizes;
      if (currentGender) {
        filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
      }
      if (filteredSizes.length > 0) {
        sizeOptions = filteredSizes.map(s => {
          const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
          return `<option value="${s.size_value}" ${s.size_value === sizeValue ? 'selected' : ''}>${s.size_value}${genderLabel}</option>`;
        }).join('');
      }
    }

    const hasSizes = sizeOptions !== '';
    const sizeInputHtml = hasSizes 
      ? `<select class="form-select form-select-sm size-value-input" required>
           <option value="">Размер...</option>
           ${sizeOptions}
         </select>`
      : `<input type="text" class="form-control form-control-sm size-value-input" value="${sizeValue}" placeholder="Размер" required maxlength="50">`;

    tr.innerHTML = `
      <td><select class="form-select form-select-sm ppe-item-select" required><option value="">Выберите СИЗ...</option>${options}</select></td>
      <td>${sizeInputHtml}</td>
      <td class="text-center"><button type="button" class="btn btn-sm btn-outline-danger remove-size-btn">✕</button></td>
    `;
    
    const itemSelect = tr.querySelector('.ppe-item-select');
    itemSelect.addEventListener('change', async () => {
      const newItemId = Number(itemSelect.value);
      if (newItemId) {
        const sizes = await getSizesForItem(newItemId);
        const currentGender = form.elements['gender'].value || null;
        let filteredSizes = sizes;
        if (currentGender) filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
        
        const sizeCell = tr.children[1];
        if (filteredSizes.length > 0) {
          const opts = '<option value="">Размер...</option>' + filteredSizes.map(s => {
            const g = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
            return `<option value="${s.size_value}">${s.size_value}${g}</option>`;
          }).join('');
          sizeCell.innerHTML = `<select class="form-select form-select-sm size-value-input" required>${opts}</select>`;
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

      const FIELDS = ['personnel_number', 'last_name', 'first_name', 'middle_name', 'hire_date', 'position_change_date', 'gender', 'height'];
      for (const f of FIELDS) {
        if (form.elements[f]) {
          if (f.includes('_date') && emp[f]) form.elements[f].value = emp[f].split('T')[0];
          else form.elements[f].value = emp[f] ?? '';
        }
      }
      
      deptSelect.value = emp.department_id ?? '';
      await loadPositions(emp.department_id, emp.position_id);

      sizesTableBody.innerHTML = '';
      if (emp.ppe_sizes && emp.ppe_sizes.length > 0) {
        for (const size of emp.ppe_sizes) {
          const tr = await createSizeRow(size.ppe_item_id, size.size_value);
          sizesTableBody.appendChild(tr);
        }
      }

      versionInput.value = emp.version ?? '';
      isDirty = false;
      
      // Загружаем выдачи и нормы
      await loadIssues();
      await loadNorms(emp.position_id);

      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // --- Загрузка норм ---
  async function loadNorms(positionId) {
    if (!positionId) {
      normsTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-2">У сотрудника не указана должность</td></tr>`;
      return;
    }
    try {
      const allNorms = await API.get('/api/v1/position_ppe_norms');
      currentNorms = allNorms.filter(n => n.position_id === Number(positionId));
      renderNormsTable();
    } catch (err) {
      normsTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-2">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderNormsTable() {
    if (!currentNorms.length) {
      normsTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-2">Для этой должности нормы не заданы</td></tr>`;
      return;
    }

    normsTableBody.innerHTML = currentNorms.map(norm => {
      // Считаем, сколько выдано по этой норме
      const issued = currentIssues
        .filter(i => i.ppe_item_id === norm.ppe_item_id)
        .reduce((sum, i) => sum + (parseInt(i.quantity) || 1), 0); // Упрощенно считаем количество

      const requiredQty = parseInt(norm.quantity) || 1;
      const remaining = requiredQty - issued;
      
      let statusClass = '';
      let statusText = '';
      if (remaining <= 0) {
        statusClass = 'text-success fw-bold';
        statusText = 'Выдано';
      } else {
        statusClass = 'text-danger fw-bold';
        statusText = `Не хватает ${remaining}`;
      }

      const periodStr = `${norm.wear_period_value} ${norm.wear_period_unit}`;

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${periodStr} (${requiredQty} ${norm.quantity.includes('пар') ? 'пар' : 'шт'})</td>
          <td>${issued}</td>
          <td class="${statusClass}">${statusText}</td>
          <td class="text-center">
            ${remaining > 0 ? `<button class="btn btn-sm btn-outline-success" onclick="openIssueModalForNorm(${norm.ppe_item_id})" title="Выдать"><i class="bi bi-box-arrow-up"></i></button>` : ''}
          </td>
        </tr>
      `;
    }).join('');
  }

  // --- Выдачи ---
  async function loadIssues() {
    try {
      currentIssues = await API.get(`/api/v1/employee_ppe_issues/?employee_id=${employeeId}`);
      renderIssuesTable();
      renderNormsTable(); // Обновляем таблицу норм, чтобы пересчитать "Осталось"
    } catch (err) {
      console.error('Ошибка загрузки выдач:', err);
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-2">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderIssuesTable() {
    if (!currentIssues || !currentIssues.length) {
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-2">Нет выданных СИЗ</td></tr>`;
      return;
    }
    issuesTableBody.innerHTML = currentIssues.map(issue => {
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

  // --- Открытие модалки выдачи из строки нормы ---
  window.openIssueModalForNorm = (ppeItemId) => {
    const modal = new bootstrap.Modal(document.getElementById('issueModal'));
    
    // Загружаем список СИЗ, если он еще не загружен
    fetch('/api/v1/ppe_items')
      .then(r => r.json())
      .then(data => {
        const select = document.getElementById('issue-item-select');
        select.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
          data.map(i => `<option value="${i.id}" ${i.id === ppeItemId ? 'selected' : ''}>${i.name} (${i.category?.name ?? ''})</option>`).join('');
        
        modal.show();
      });
  };

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
        await loadIssues(); // Перезагружаем выдачи и нормы
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
      await loadIssues(); // Перезагружаем
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

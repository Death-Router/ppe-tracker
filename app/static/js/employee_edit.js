(() => {
  console.log('🚀 employee_edit.js загружен (финальная версия)');
  
  const employeeId = window.EMPLOYEE_ID;
  const form = document.getElementById('employee-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const deptSelect = document.getElementById('department_id');
  const posSelect = document.getElementById('position_id');
  const genderSelect = form.elements['gender']; 
  
  const sizesTableBody = document.querySelector('#sizes-table tbody');
  const addSizeBtn = document.getElementById('add-size-btn');

  const issueForm = document.getElementById('issue-form');
  const issuesTableBody = document.querySelector('#issues-table tbody');
  const normsTableBody = document.querySelector('#norms-table tbody');
  
  // Новые элементы для выдачи (datalist)
  const issueItemInput = document.getElementById('issue-item-input');
  const issueItemIdInput = document.getElementById('issue-item-id');
  const issuePpeList = document.getElementById('issue-ppe-list');
  const issueSizeSelect = document.getElementById('issue-size-select');
  
  let allSizeGroups = [];
  let allPpeItems = [];
  let allSizesCache = {};
  let currentNorms = [];
  let currentIssues = [];
  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  // --- Утилиты склонения ---
  function formatPeriod(value, unit) {
    if (!value) return '—';
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${unit}`;
    if (unit === 'год') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} лет`;
      if (lastDigit === 1) return `${num} год`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} года`;
      return `${num} лет`;
    }
    if (unit === 'месяц') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} месяцев`;
      if (lastDigit === 1) return `${num} месяц`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} месяца`;
      return `${num} месяцев`;
    }
    if (unit === 'день') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} дней`;
      if (lastDigit === 1) return `${num} день`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} дня`;
      return `${num} дней`;
    }
    if (unit === 'смена') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} смен`;
      if (lastDigit === 1) return `${num} смена`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} смены`;
      return `${num} смен`;
    }
    return `${value} ${unit}`;
  }

  function formatUnit(value, shortName) {
    if (!shortName) return value;
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${shortName}`;
    if (shortName.toLowerCase() === 'пара') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} пар`;
      if (lastDigit === 1) return `${num} пара`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} пары`;
      return `${num} пар`;
    }
    if (shortName.toLowerCase() === 'штука' || shortName.toLowerCase() === 'шт') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} штук`;
      if (lastDigit === 1) return `${num} штука`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} штуки`;
      return `${num} штук`;
    }
    if (shortName.toLowerCase() === 'комплект') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} комплектов`;
      if (lastDigit === 1) return `${num} комплект`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} комплекта`;
      return `${num} комплектов`;
    }
    return `${num} ${shortName}`;
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  // --- Загрузка справочников ---

  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    filtered.sort((a, b) => a.name.localeCompare(b.name));
    for (const dept of filtered) {
      result.push({ ...dept, level });
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }


  function buildDeptPath(deptId, allDepts) {
    if (!deptId) return '';
    const dept = allDepts.find(d => d.id === deptId);
    if (!dept) return '';
    const parentPath = dept.parent_id ? buildDeptPath(dept.parent_id, allDepts) : '';
    return parentPath ? `${parentPath} / ${dept.name}` : dept.name;
  }

  let allDepartments = [];

  async function loadDepartments() {
    allDepartments = await API.get('/api/v1/departments');
    const hierarchy = buildHierarchy(allDepartments);
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
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

  async function loadSizeGroups() {
    allSizeGroups = await API.get('/api/v1/ppe_size_groups');
  }

  async function loadAllPpeItems() {
    allPpeItems = await API.get('/api/v1/ppe_items');
  }

  async function getSizesForCategory(categoryId) {
    if (allSizesCache[categoryId]) return allSizesCache[categoryId];
    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${categoryId}`);
      allSizesCache[categoryId] = sizes;
      return sizes;
    } catch (err) {
      return [];
    }
  }

  deptSelect.addEventListener('change', async (e) => {
    await loadPositions(e.target.value);
    window.FormValidation.refresh();
  });

  // --- Управление размерами (по категориям) ---
  async function createSizeRow(categoryId = '', sizeValue = '') {
    const tr = document.createElement('tr');
    const currentGender = genderSelect.value || null;
    
    const sizeGroupOptions = allSizeGroups.map(g => 
      `<option value="${g.id}" ${g.id === Number(categoryId) ? 'selected' : ''}>${g.name}</option>`
    ).join('');

    let sizeOptionsHtml = '';
    if (categoryId) {
      const sizes = await getSizesForCategory(categoryId);
      let filteredSizes = sizes;
      if (currentGender) {
        filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
      }
      if (filteredSizes.length > 0) {
        sizeOptionsHtml = '<option value="">Размер...</option>' + 
          filteredSizes.map(s => {
            const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
            return `<option value="${s.size_value}" ${s.size_value === sizeValue ? 'selected' : ''}>${s.size_value}${genderLabel}</option>`;
          }).join('');
      }
    }

    const hasSizes = sizeOptionsHtml !== '';
    const sizeInputHtml = hasSizes 
      ? `<select class="form-select form-select-sm size-value-input" required>${sizeOptionsHtml}</select>`
      : `<input type="text" class="form-control form-control-sm size-value-input" value="${sizeValue}" placeholder="Размер" required maxlength="50">`;

    tr.innerHTML = `
      <td>
        <select class="form-select form-select-sm size-group-select" required>
          <option value="">Выберите размерную группу...</option>
          ${sizeGroupOptions}
        </select>
      </td>
      <td>${sizeInputHtml}</td>
      <td class="text-center"><button type="button" class="btn btn-icon btn-icon--danger remove-size-btn">✕</button></td>
    `;
    
    const catSelect = tr.querySelector('.size-group-select');
    catSelect.addEventListener('change', async () => {
      const newCatId = Number(catSelect.value);
      const sizeCell = tr.children[1];
      if (newCatId) {
        const sizes = await getSizesForCategory(newCatId);
        const currentGender = genderSelect.value || null;
        let filteredSizes = sizes;
        if (currentGender) filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
        if (filteredSizes.length > 0) {
          const opts = '<option value="">Размер...</option>' + 
            filteredSizes.map(s => {
              const g = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
              return `<option value="${s.size_value}">${s.size_value}${g}</option>`;
            }).join('');
          sizeCell.innerHTML = `<select class="form-select form-select-sm size-value-input" required>${opts}</select>`;
        } else {
          sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
        }
      } else {
        sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
      }
    });
    
    tr.querySelector('.remove-size-btn').addEventListener('click', () => {
      tr.remove();
      isDirty = true;
      window.FormValidation.refresh();
    });
    return tr;
  }

  addSizeBtn.addEventListener('click', async () => {
    const tr = await createSizeRow();
    sizesTableBody.appendChild(tr);
    isDirty = true;
    window.FormValidation.refresh();
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

      // Отрисовка размеров
      sizesTableBody.innerHTML = '';
      if (emp.ppe_sizes && emp.ppe_sizes.length > 0) {
        for (const size of emp.ppe_sizes) {
          const tr = await createSizeRow(size.size_group_id, size.size_value);
          sizesTableBody.appendChild(tr);
        }
      }

      versionInput.value = emp.version ?? '';
      isDirty = false;
      window.FormValidation.refresh();

      // Меняем заголовок на ФИО
      const titleEl = document.getElementById('employee-title');
      if (titleEl) {
        const fio = [emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ');
        titleEl.textContent = `Редактирование: ${fio}`;
        // Обновляем путь к подразделению
        const deptPathEl = document.getElementById('employee-dept-path');
        if (deptPathEl) {
          if (emp.department_id && allDepartments.length) {
            deptPathEl.textContent = buildDeptPath(emp.department_id, allDepartments);
          } else {
            deptPathEl.textContent = '';
          }
        }
      }
      
      await loadIssues();
      await loadNorms(emp.position_id);

      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // --- Нормы ---
  async function loadNorms(positionId) {
    if (!positionId) {
      normsTableBody.innerHTML = `<tr><td colspan="5" class="state">У сотрудника не указана должность</td></tr>`;
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
      normsTableBody.innerHTML = `<tr><td colspan="5" class="state">Для этой должности нормы не заданы</td></tr>`;
      return;
    }
    normsTableBody.innerHTML = currentNorms.map(norm => {
      const issued = currentIssues
        .filter(i => i.ppe_item_id === norm.ppe_item_id)
        .reduce((sum, i) => sum + (parseInt(i.quantity) || 1), 0);
      const requiredQty = parseInt(norm.quantity) || 1;
      const remaining = requiredQty - issued;
      
      let statusClass = remaining <= 0 ? 'text-success fw-bold' : 'text-danger fw-bold';
      let statusText = remaining <= 0 ? 'Выдано' : `Не хватает ${remaining}`;

      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedQuantity} на ${formattedPeriod}</td>
          <td>${issued}</td>
          <td class="${statusClass}">${statusText}</td>
          <td class="text-center">
            ${remaining > 0 ? `<button class="btn btn-icon" onclick="openIssueModalForNorm(${norm.ppe_item_id})" title="Выдать"><i class="bi bi-box-arrow-up"></i></button>` : ''}
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
      renderNormsTable(); 
    } catch (err) {
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-2">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderIssuesTable() {
    if (!currentIssues || !currentIssues.length) {
      issuesTableBody.innerHTML = `<tr><td colspan="5" class="state">Нет выданных СИЗ</td></tr>`;
      return;
    }
    issuesTableBody.innerHTML = currentIssues.map(issue => {
      const isExpired = issue.expiry_date && new Date(issue.expiry_date) < new Date();
      const rowClass = isExpired ? 'table-danger' : '';
      const expiryStr = issue.expiry_date ? new Date(issue.expiry_date).toLocaleDateString('ru-RU') : '—';
      
      const formattedQuantity = formatUnit(issue.quantity, issue.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr class="${rowClass}">
          <td>${issue.ppe_item?.name ?? '—'}</td>
          <td>${new Date(issue.issue_date).toLocaleDateString('ru-RU')}</td>
          <td>${expiryStr}</td>
          <td>${formattedQuantity}</td>
          <td class="text-center"><button type="button" class="btn btn-icon btn-icon--danger" onclick="deleteIssue(${issue.id})">✕</button></td>
        </tr>
      `;
    }).join('');
  }

  // --- Модалка выдачи (datalist) ---
  window.openIssueModalForNorm = (ppeItemId) => {
    const modal = new bootstrap.Modal(document.getElementById('issueModal'));
    
    fetch('/api/v1/ppe_items')
      .then(r => r.json())
      .then(data => {
        if (issuePpeList) {
          issuePpeList.innerHTML = data.map(i => 
            `<option value="${i.name} (${i.category?.name ?? ''})" data-id="${i.id}" data-category-id="${i.category_id}"></option>`
          ).join('');
        }

        if (ppeItemId) {
          const item = data.find(i => i.id === ppeItemId);
          if (item && issueItemInput) {
            issueItemInput.value = `${item.name} (${item.category?.name ?? ''})`;
            issueItemIdInput.value = item.id;
            fillIssueSizes(item.category_id);
            const unitLabel = document.getElementById('issue-unit-label');
            if (item.unit) unitLabel.textContent = item.unit.short_name;
          }
        }
        
        modal.show();
      });
  };

  async function fillIssueSizes(categoryId) {
    if (!categoryId) {
      issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
      return;
    }
    try {
      const sizes = await getSizesForCategory(categoryId);
      const empGender = genderSelect.value || null;
      let filteredSizes = sizes;
      if (empGender) filteredSizes = sizes.filter(s => !s.gender || s.gender === empGender);
      
      if (filteredSizes.length > 0) {
        let opts = '<option value="">Выберите размер...</option>';
        let defaultSize = '';
        const sizeRows = sizesTableBody.querySelectorAll('tr');
        sizeRows.forEach(row => {
          const catSel = row.querySelector('.category-select');
          const sizeInp = row.querySelector('.size-value-input');
          if (catSel && sizeInp && Number(catSel.value) === Number(categoryId)) {
             defaultSize = sizeInp.value;
          }
        });
        opts += filteredSizes.map(s => {
          const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
          const selected = s.size_value === defaultSize ? 'selected' : '';
          return `<option value="${s.size_value}" ${selected}>${s.size_value}${genderLabel}</option>`;
        }).join('');
        issueSizeSelect.innerHTML = opts;
      } else {
        issueSizeSelect.innerHTML = '<option value="">Нет размеров</option>';
      }
    } catch (err) {
      issueSizeSelect.innerHTML = '<option value="">Ошибка</option>';
    }
  }

  const issueModalElement = document.getElementById('issueModal');
  if (issueModalElement) {
    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          if (issuePpeList) {
            issuePpeList.innerHTML = data.map(i => 
              `<option value="${i.name} (${i.category?.name ?? ''})" data-id="${i.id}" data-category-id="${i.category_id}"></option>`
            ).join('');
          }
          if (issueItemInput) issueItemInput.value = '';
          if (issueItemIdInput) issueItemIdInput.value = '';
          if (issueSizeSelect) issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
        });
    });

    if (issueItemInput) {
      issueItemInput.addEventListener('input', (e) => {
        const val = e.target.value;
        const option = Array.from(issuePpeList.options).find(opt => opt.value === val);
        if (option) {
          const itemId = option.getAttribute('data-id');
          const categoryId = option.getAttribute('data-category-id');
          issueItemIdInput.value = itemId;
          fillIssueSizes(categoryId);
          
          const selectedItem = allPpeItems.find(i => i.id === Number(itemId));
          const unitLabel = document.getElementById('issue-unit-label');
          if (selectedItem && selectedItem.unit) unitLabel.textContent = selectedItem.unit.short_name;
          else unitLabel.textContent = 'ед.';
        } else {
          issueItemIdInput.value = '';
        }
      });
    }
  }

  // Функция для отправки формы выдачи
  window.submitIssueForm = async (event) => {
    if (event) event.preventDefault();
    const formEl = document.getElementById('issue-form');
    if (!formEl) return;

    const payload = FormHelper.serialize(formEl);
    payload.employee_id = employeeId;
    payload.ppe_item_id = Number(issueItemIdInput.value);
    
    if (!payload.ppe_item_id) {
      window.showToast('Выберите СИЗ из списка', 'danger');
      return;
    }
    if (!payload.issue_date) payload.issue_date = new Date().toISOString().split('T')[0];
    if (payload.size_value === '') payload.size_value = null;

    const btn = document.querySelector('button[onclick="submitIssueForm(event)"]');
    if (btn) btn.disabled = true;

    try {
      await API.post('/api/v1/employee_ppe_issues/', payload);
      window.showToast('СИЗ выдано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('issueModal')).hide();
      formEl.reset();
      issueItemIdInput.value = '';
      issueItemInput.value = '';
      await loadIssues();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  };

  window.deleteIssue = async (issueId) => {
    if (!confirm('Удалить запись о выдаче?')) return;
    try {
      await API.request(`/api/v1/employee_ppe_issues/${issueId}`, { method: 'DELETE' });
      window.showToast('Запись удалена', 'success');
      await loadIssues();
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
      const catSelect = tr.querySelector('.size-group-select');
      const sizeInput = tr.querySelector('.size-value-input');
      const categoryId = Number(catSelect.value);
      const sizeVal = sizeInput.value.trim();
      if (!categoryId || !sizeVal) {
        hasErrors = true;
        catSelect.classList.add('is-invalid');
        sizeInput.classList.add('is-invalid');
      } else {
        ppeSizes.push({ size_group_id: categoryId, size_value: sizeVal });
      }
    });

    if (hasErrors) {
      window.showToast('Заполните все поля в таблице размеров', 'danger');
      window.FormValidation.refresh();
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
      window.FormValidation.refresh();
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'employee_updated' && data.employee_id === employeeId) loadEmployee(true);
    if (data.event === 'issue_updated') loadIssues();
  });

  // Инициализация
  loadDepartments()
    .then(loadSizeGroups)
    .then(loadAllPpeItems)
    .then(() => loadEmployee());
})();

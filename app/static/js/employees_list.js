(() => {
  const tbody = document.querySelector('#employees-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');
  const createPosSelect = document.getElementById('create-pos');
  const searchInput = document.getElementById('search-input');
  const pagerEl = document.getElementById('pager');

  const PAGE_SIZE = 20;
  let currentPage = 1;
  let searchTerm = '';
  let searchTimer = null;

  async function loadEmployees(page = currentPage) {
    currentPage = page;
    try {
      const params = new URLSearchParams({
        paginated: 'true',
        page: String(currentPage),
        page_size: String(PAGE_SIZE),
      });
      if (searchTerm) params.set('search', searchTerm);

      const data = await API.get(`/api/v1/employees/?${params.toString()}`);

      // Если страница опустела после удаления — уходим на предыдущую
      if (!data.items.length && data.total > 0 && currentPage > 1) {
        return loadEmployees(currentPage - 1);
      }

      renderTable(data.items);
      Pager.render(pagerEl, data, loadEmployees);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="state state--error">Ошибка: ${escapeHtml(err.message)}</td></tr>`;
      if (pagerEl) pagerEl.innerHTML = '';
    }
  }

  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      // Пауза после ввода: иначе на каждую букву уходит запрос в БД
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        searchTerm = e.target.value.trim();
        loadEmployees(1);
      }, 300);
    });
  }

  function renderTable(employees) {
    if (!employees.length) {
      const text = searchTerm
        ? `По запросу «${escapeHtml(searchTerm)}» ничего не найдено`
        : 'Сотрудников пока нет';
      tbody.innerHTML = `<tr><td colspan="5" class="state">${text}</td></tr>`;
      return;
    }
    tbody.innerHTML = employees.map(e => {
      const fio = `${e.last_name} ${e.first_name} ${e.middle_name ?? ''}`.trim();
      return `
      <tr data-employee-id="${e.id}">
        <td>${escapeHtml(fio)}</td>
        <td class="cell-mono">${escapeHtml(e.personnel_number)}</td>
        <td>${escapeHtml(e.department_rel?.name ?? '—')}</td>
        <td>${escapeHtml(e.position_rel?.name ?? '—')}</td>
        <td class="col-actions">
          <button class="btn btn-icon js-edit-employee" data-id="${e.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger js-delete-employee" data-id="${e.id}" data-fio="${escapeHtml(fio)}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  // ФИО передаём через data-атрибут, а не в onclick: подстановка строки в JS-код
  // ломалась на именах с кавычками (и позволяла внедрить код).
  tbody.addEventListener('click', (event) => {
    const edit = event.target.closest('.js-edit-employee');
    if (edit) {
      window.openEditEmployee(Number(edit.dataset.id));
      return;
    }
    const del = event.target.closest('.js-delete-employee');
    if (del) window.deleteEmployee(Number(del.dataset.id), del.dataset.fio);
  });

  async function loadDepartmentsForSelect() {
    try {
      const depts = await API.get('/api/v1/departments');
      createDeptSelect.innerHTML = '<option value="">Подразделение</option>' +
        depts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
    } catch (err) {
      createDeptSelect.innerHTML = '<option value="">Ошибка</option>';
    }
  }

  async function loadPositionsForSelect(deptId, selectedId = null) {
    if (!deptId) {
      createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
      return;
    }
    try {
      const positions = await API.get('/api/v1/positions');
      const filtered = positions.filter(p => p.department_id === Number(deptId));
      createPosSelect.innerHTML = '<option value="">Должность</option>' +
        filtered.map(p => `<option value="${p.id}" ${Number(selectedId) === p.id ? 'selected' : ''}>${escapeHtml(p.name)}</option>`).join('');
    } catch (err) {
      createPosSelect.innerHTML = '<option value="">Ошибка</option>';
    }
  }

  // --- Строка размера в модалке ----------------------------------------
  let allSizeGroupsCache = null;

  async function getSizeGroups() {
    if (!allSizeGroupsCache) {
      allSizeGroupsCache = await API.get('/api/v1/ppe_size_groups');
    }
    return allSizeGroupsCache;
  }

  // Строка размера: группа и значение. Если для группы заданы готовые
  // размеры — это выпадающий список, иначе поле ввода.
  async function buildSizeRow(groupId = '', sizeValue = '') {
    const groups = await getSizeGroups();
    const tr = document.createElement('tr');

    const groupOptions = groups
      .map((g) => `<option value="${g.id}" ${g.id === Number(groupId) ? 'selected' : ''}>${escapeHtml(g.name)}</option>`)
      .join('');

    const gender = createForm.elements['gender']?.value || null;
    let sizeCell = `<input type="text" class="form-control form-control-sm size-value-input" value="${escapeHtml(sizeValue)}" placeholder="Размер" maxlength="50">`;

    if (groupId) {
      try {
        const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
        const filtered = gender ? sizes.filter((s) => !s.gender || s.gender === gender) : sizes;
        if (filtered.length) {
          sizeCell = `<select class="form-select form-select-sm size-value-input">
            <option value="">Размер...</option>
            ${filtered.map((s) => {
              const label = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
              const sel = s.size_value === sizeValue ? 'selected' : '';
              return `<option value="${escapeHtml(s.size_value)}" ${sel}>${escapeHtml(s.size_value)}${label}</option>`;
            }).join('')}
          </select>`;
        }
      } catch (err) {
        // останется поле ввода — это допустимый вариант
      }
    }

    tr.innerHTML = `
      <td>
        <select class="form-select form-select-sm size-group-select">
          <option value="">Выберите размерную группу...</option>
          ${groupOptions}
        </select>
      </td>
      <td>${sizeCell}</td>
      <td class="col-actions">
        <button type="button" class="btn btn-icon btn-icon--danger remove-size-btn" title="Удалить размер">
          <i class="bi bi-trash"></i>
        </button>
      </td>
    `;

    // При смене группы перестраиваем значение размера
    const groupSel = tr.querySelector('.size-group-select');
    groupSel.addEventListener('change', async () => {
      const replacement = await buildSizeRow(groupSel.value);
      tr.replaceWith(replacement);
    });

    return tr;
  }

  createDeptSelect.addEventListener('change', (e) => {
    loadPositionsForSelect(e.target.value);
  });

  // --- Модалка сотрудника: создание и редактирование -------------------
  const modalEl = document.getElementById('employeeModal');
  const modalTitle = document.getElementById('employee-modal-title');
  const saveBtn = document.getElementById('emp-save-btn');
  const versionInput = document.getElementById('emp-version');
  const sizesBody = document.getElementById('emp-sizes-body');
  const normsBody = document.querySelector('#emp-norms-table tbody');
  const issuesBody = document.querySelector('#emp-issues-table tbody');
  const normsTabItem = document.getElementById('emp-tab-norms-item');
  const issuesTabItem = document.getElementById('emp-issues-item');

  let editingId = null;
  let currentEmployee = null;

  function resetModal() {
    createForm.reset();
    versionInput.value = '';
    sizesBody.innerHTML = '';
    normsBody.innerHTML = '<tr><td colspan="4" class="state">Нет данных</td></tr>';
    issuesBody.innerHTML = '<tr><td colspan="4" class="state">Нет данных</td></tr>';
    createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
    // Возвращаемся на первую вкладку
    bootstrap.Tab.getOrCreateInstance(
      document.querySelector('#employeeModalTabs [data-bs-target="#emp-tab-main"]')
    ).show();
    window.FormValidation.refresh();
  }

  function setEditOnlyTabs(visible) {
    [normsTabItem, issuesTabItem].forEach((el) => {
      if (el) el.classList.toggle('d-none', !visible);
    });
  }

  window.openCreateEmployee = () => {
    editingId = null;
    currentEmployee = null;
    modalTitle.textContent = 'Новый сотрудник';
    saveBtn.textContent = 'Создать';
    setEditOnlyTabs(false);
    resetModal();
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
  };

  window.openEditEmployee = async (id) => {
    try {
      const emp = await API.get(`/api/v1/employees/${id}`);
      editingId = id;
      currentEmployee = emp;

      modalTitle.textContent = `Редактирование: ${[emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ')}`;
      saveBtn.textContent = 'Сохранить';
      setEditOnlyTabs(true);
      resetModal();

      const FIELDS = ['personnel_number', 'last_name', 'first_name', 'middle_name', 'hire_date', 'position_change_date', 'gender', 'height'];
      FIELDS.forEach((f) => {
        const input = createForm.elements[f];
        if (!input) return;
        input.value = f.includes('_date') && emp[f] ? emp[f].split('T')[0] : (emp[f] ?? '');
      });

      createDeptSelect.value = emp.department_id ?? '';
      await loadPositionsForSelect(emp.department_id, emp.position_id);

      versionInput.value = emp.version ?? '';

      for (const size of emp.ppe_sizes ?? []) {
        sizesBody.appendChild(await buildSizeRow(size.size_group_id, size.size_value));
      }
      renderNormsAndIssues(emp);

      bootstrap.Modal.getOrCreateInstance(modalEl).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Нормы и выдачи на своих вкладках: только для просмотра
  function renderNormsAndIssues(emp) {
    const norms = emp.position_ppe_norms ?? emp.norms ?? [];
    normsBody.innerHTML = norms.length
      ? norms.map((n) => `<tr>
          <td>${escapeHtml(n.ppe_item?.name ?? '—')}</td>
          <td>${escapeHtml(String(n.quantity ?? '—'))}</td>
          <td>${escapeHtml(String(n.issued ?? '—'))}</td>
          <td>${escapeHtml(String(n.remaining ?? '—'))}</td>
        </tr>`).join('')
      : '<tr><td colspan="4" class="state">Нормы не заданы</td></tr>';

    const issues = emp.ppe_issues ?? emp.issues ?? [];
    issuesBody.innerHTML = issues.length
      ? issues.map((i) => `<tr>
          <td>${escapeHtml(i.ppe_item?.name ?? '—')}</td>
          <td>${escapeHtml(i.size_value ?? '—')}</td>
          <td>${escapeHtml((i.issue_date ?? '').split('T')[0] || '—')}</td>
          <td>${escapeHtml((i.write_off_date ?? '').split('T')[0] || '—')}</td>
        </tr>`).join('')
      : '<tr><td colspan="4" class="state">Выдач пока нет</td></tr>';
  }

  document.getElementById('btn-add-employee')?.addEventListener('click', window.openCreateEmployee);
  document.getElementById('emp-add-size')?.addEventListener('click', async () => {
    sizesBody.appendChild(await buildSizeRow());
  });

  sizesBody.addEventListener('click', (event) => {
    const btn = event.target.closest('.remove-size-btn');
    if (btn) btn.closest('tr').remove();
  });

  saveBtn.addEventListener('click', async () => {
    // Валидируем только поля основной вкладки: размеры проверяем отдельно
    if (!createForm.reportValidity()) {
      bootstrap.Tab.getOrCreateInstance(
        document.querySelector('#employeeModalTabs [data-bs-target="#emp-tab-main"]')
      ).show();
      return;
    }

    const ppeSizes = [];
    let sizeError = false;
    sizesBody.querySelectorAll('tr').forEach((tr) => {
      const group = tr.querySelector('.size-group-select');
      const value = tr.querySelector('.size-value-input');
      const groupId = Number(group?.value);
      const sizeVal = value?.value.trim() ?? '';
      if (!groupId || !sizeVal) {
        sizeError = true;
        return;
      }
      ppeSizes.push({ size_group_id: groupId, size_value: sizeVal });
    });

    if (sizeError) {
      bootstrap.Tab.getOrCreateInstance(
        document.querySelector('#employeeModalTabs [data-bs-target="#emp-tab-sizes"]')
      ).show();
      window.showToast('Заполните все поля в таблице размеров', 'danger');
      return;
    }

    const payload = FormHelper.serialize(createForm);
    payload.department_id = Number(payload.department_id);
    payload.position_id = Number(payload.position_id);
    if (!payload.hire_date) payload.hire_date = null;
    if (!payload.position_change_date) payload.position_change_date = null;
    payload.ppe_sizes = ppeSizes;

    saveBtn.disabled = true;
    try {
      if (editingId) {
        payload.version = Number(versionInput.value);
        await API.put(`/api/v1/employees/${editingId}`, payload);
        window.showToast('Сотрудник сохранён', 'success');
      } else {
        await API.post('/api/v1/employees/', payload);
        window.showToast('Сотрудник создан', 'success');
      }
      bootstrap.Modal.getOrCreateInstance(modalEl).hide();
      loadEmployees();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      saveBtn.disabled = false;
      window.FormValidation.refresh();
    }
  });

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

(() => {
  const tbody = document.querySelector('#employees-table tbody');
  const createForm = document.getElementById('employee-form');
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

    // Размер выбирается только из справочника: ручной ввод давал значения
    // вроде «58 размер» мимо таблицы размеров, и потом они не совпадали при
    // выдаче СИЗ. Если для группы размеров нет — предлагаем их задать, а не
    // вводить наугад.
    let sizeCell = `<select class="form-select form-select-sm size-value-input" disabled>
        <option value="">Сначала выберите группу</option>
      </select>`;

    if (groupId) {
      try {
        const sizes = await API.get(
          `/api/v1/ppe_sizes/?size_group_id=${groupId}${gender ? `&gender=${encodeURIComponent(gender)}` : ''}`
        );
        // В справочнике размер может быть без указания пола — он подходит обоим
        const filtered = gender ? sizes.filter((s) => !s.gender || s.gender === gender) : sizes;

        sizeCell = filtered.length
          ? `<select class="form-select form-select-sm size-value-input">
              <option value="">Размер...</option>
              ${filtered.map((s) => {
                const label = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
                const sel = s.size_value === sizeValue ? 'selected' : '';
                return `<option value="${escapeHtml(s.size_value)}" ${sel}>${escapeHtml(s.size_value)}${label}</option>`;
              }).join('')}
            </select>`
          : `<select class="form-select form-select-sm size-value-input is-invalid" disabled>
              <option value="">В группе нет размеров</option>
            </select>`;
      } catch (err) {
        sizeCell = `<select class="form-select form-select-sm size-value-input is-invalid" disabled>
            <option value="">Не удалось загрузить размеры</option>
          </select>`;
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
  const issuesBody = document.querySelector('#emp-issues-table tbody');
  const issuesTabItem = document.getElementById('emp-tab-issues-item');

  let editingId = null;
  let currentEmployee = null;

  function resetModal() {
    createForm.reset();
    versionInput.value = '';
    sizesBody.innerHTML = '';
    issuesBody.innerHTML = '<tr><td colspan="4" class="state">Нет данных</td></tr>';
    createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
    // Возвращаемся на первую вкладку
    bootstrap.Tab.getOrCreateInstance(
      document.querySelector('#employeeModalTabs [data-bs-target="#emp-tab-main"]')
    ).show();
    window.FormValidation.refresh();
  }

  // Вкладка выдач появляется только при редактировании: у нового сотрудника
  // их быть не может. Нормы переехали в отдельный раздел навбара.
  function setEditOnlyTabs(visible) {
    if (issuesTabItem) issuesTabItem.classList.toggle('d-none', !visible);
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
      renderIssues(emp);

      bootstrap.Modal.getOrCreateInstance(modalEl).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Выдачи на своей вкладке: только для просмотра
  function renderIssues(emp) {
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
    // Одна размерная группа — один размер. Проверяем сразу, не дожидаясь
    // ответа сервера: раньше дубликат давал голое «HTTP 500»
    const usedGroups = new Map();

    sizesBody.querySelectorAll('tr').forEach((tr) => {
      const group = tr.querySelector('.size-group-select');
      const value = tr.querySelector('.size-value-input');
      const groupId = Number(group?.value);
      const sizeVal = value?.value.trim() ?? '';

      group?.classList.remove('is-invalid');

      if (!groupId || !sizeVal) {
        sizeError = true;
        return;
      }

      if (usedGroups.has(groupId)) {
        group.classList.add('is-invalid');
        const groupName = group.selectedOptions?.[0]?.textContent?.trim() ?? 'этой группы';
        window.showToast(
          `В карточке сотрудника уже есть размер для группы «${groupName}». ` +
          'Для каждой размерной группы допускается только один размер.',
          'danger'
        );
        sizeError = true;
        return;
      }

      usedGroups.set(groupId, true);
      ppeSizes.push({ size_group_id: groupId, size_value: sizeVal });
    });

    if (sizeError) {
      bootstrap.Tab.getOrCreateInstance(
        document.querySelector('#employeeModalTabs [data-bs-target="#emp-tab-sizes"]')
      ).show();
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

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
      tableState(tbody, 5, `Ошибка: ${err.message}`, { error: true });
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

  // Версия в адресе сбрасывает кэш после замены фото; при ошибке загрузки
  // (файл не доехал вместе с томом) показываем силуэт, а не «битую» картинку
  function photoUrl(employee) {
    const version = employee?.photo?.uploaded_at
      ? `?v=${encodeURIComponent(employee.photo.uploaded_at)}`
      : '';
    return `/api/v1/employees/${employee.id}/photo${version}`;
  }

  // Значок-заглушка: используется и когда фото нет в БД, и когда файл не найден
  const AVATAR_EMPTY = '<span class="avatar avatar--empty"><i class="bi bi-person"></i></span>';

  function renderTable(employees) {
    if (!employees.length) {
      const text = searchTerm
        ? `По запросу «${searchTerm}» ничего не найдено`
        : 'Сотрудников пока нет';
      tableState(tbody, 5, text);
      return;
    }
    tbody.innerHTML = employees.map(e => {
      const fio = `${e.last_name} ${e.first_name} ${e.middle_name ?? ''}`.trim();
      // Фото грузим лениво: в списке 20 строк, и каждая — отдельный запрос
      const avatar = e.photo
        ? `<img class="avatar" src="${photoUrl(e)}" alt="" loading="lazy">`
        : AVATAR_EMPTY;
      return `
      <tr data-employee-id="${e.id}">
        <td><div class="cell-person">${avatar}<span>${escapeHtml(fio)}</span></div></td>
        <td class="cell-mono">${escapeHtml(e.personnel_number)}</td>
        <td>${escapeHtml(e.department_rel?.name ?? '—')}</td>
        <td>${escapeHtml(e.position_rel?.name ?? '—')}</td>
        <td class="col-actions">
          <button class="btn btn-icon js-edit-employee" data-id="${e.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger js-delete-employee" data-id="${e.id}" data-fio="${escapeHtml(fio)}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');

    // Строка в employee_photos есть, а файла в томе может не быть (базу
    // перенесли, фото — нет): сервер ответит 404, и браузер нарисует «битую»
    // картинку. Подменяем на силуэт. Делегирование не подходит — событие
    // error не всплывает, поэтому слушатели ставим на сами картинки.
    tbody.querySelectorAll('img.avatar').forEach(img => {
      img.addEventListener('error', () => {
        img.outerHTML = AVATAR_EMPTY;
      }, { once: true });
    });
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
  const saveBtn = document.getElementById('emp-save-btn');
  const versionInput = document.getElementById('emp-version');
  const sizesBody = document.getElementById('emp-sizes-body');
  const issuesBody = document.querySelector('#emp-issues-table tbody');
  const issuesTabItem = document.getElementById('emp-tab-issues-item');
  const onHandBody = document.getElementById('emp-onhand-body');
  const normsBody = document.getElementById('emp-norms-body');
  const onHandTabItem = document.getElementById('emp-tab-onhand-item');
  const normsTabItem = document.getElementById('emp-tab-norms-item');

  let editingId = null;
  let currentEmployee = null;
  // Выдачи текущей карточки по id — нужны модалке возврата
  let issueById = new Map();

  function resetModal() {
    createForm.reset();
    versionInput.value = '';
    sizesBody.innerHTML = '';
    tableState(issuesBody, 6, 'Нет данных');
    tableState(onHandBody, 3, 'Нет данных');
    tableState(normsBody, 5, 'Нет данных');
    createPosSelect.innerHTML = '<option value="">Сначала выберите подразделение</option>';
    // Возвращаемся на первую вкладку
    TabHelper.show('#employeeModalTabs [data-bs-target="#emp-tab-main"]');
    window.FormValidation.refresh();
  }

  // Вкладка выдач нужна только когда есть должность: нормы выдачи заданы
  // должности, и без неё выдавать нечего. У нового сотрудника её тоже нет.
  function setEditOnlyTabs(isEditing) {
    if (!issuesTabItem) return;
    const hasPosition = Boolean(createForm.elements['position_id']?.value);
    const visible = isEditing && hasPosition;
    // Три вкладки живут вместе: выдачи, остатки и нормы. Без должности норм
    // нет, а значит нечего ни выдавать, ни сравнивать
    [issuesTabItem, onHandTabItem, normsTabItem].forEach((item) => {
      item?.classList.toggle('d-none', !visible);
    });
  }

  // Должность меняется прямо в модалке — вкладку показываем или скрываем сразу
  createForm.elements['position_id']?.addEventListener('change', () => {
    if (!editingId) return;
    setEditOnlyTabs(true);
    // Если вкладку скрыли, а она была открыта, вернёмся на основные данные
    if (issuesTabItem?.classList.contains('d-none')) {
      const activePane = document.querySelector('#employeeModalContent .tab-pane.active');
      const editOnly = ['emp-tab-issues', 'emp-tab-onhand', 'emp-tab-norms'];
      if (editOnly.includes(activePane?.id)) {
        TabHelper.show('#employeeModalTabs [data-bs-target="#emp-tab-main"]');
      }
    }
  });

  // --- Фото сотрудника ---------------------------------------------------
  // Файл хранится на томе, байты отдаёт API с проверкой прав. Загружать можно
  // только существующему сотруднику: фото привязано к id.
  const photoPreview = document.getElementById('emp-photo-preview');
  const photoEmpty = document.getElementById('emp-photo-empty');
  const photoInput = document.getElementById('emp-photo-input');
  const photoUploadBtn = document.getElementById('emp-photo-upload');
  const photoDeleteBtn = document.getElementById('emp-photo-delete');
  const photoHint = document.getElementById('emp-photo-hint');

  const PHOTO_HINT = 'JPEG, PNG или WebP до 5 МБ';
  const PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
  const PHOTO_MAX_MB = 5;

  function renderPhoto(employee) {
    const hasPhoto = Boolean(employee?.photo);

    if (hasPhoto) {
      photoPreview.src = photoUrl(employee);
      photoPreview.classList.remove('d-none');
      photoEmpty.classList.add('d-none');
      photoDeleteBtn.classList.remove('d-none');
    } else {
      photoPreview.removeAttribute('src');
      photoPreview.classList.add('d-none');
      photoEmpty.classList.remove('d-none');
      photoDeleteBtn.classList.add('d-none');
    }

    // Новому сотруднику фото некуда привязать — сначала сохраните карточку
    const canUpload = Boolean(employee);
    photoUploadBtn.disabled = !canUpload;
    photoHint.textContent = canUpload ? PHOTO_HINT : 'Сохраните карточку, затем загрузите фото';
    photoHint.classList.remove('text-danger');
  }

  async function uploadPhoto(file) {
    if (!file || !editingId) return;

    // Проверяем до запроса: сервер ответит 400, но так пользователь узнает сразу
    if (!PHOTO_TYPES.includes(file.type)) {
      window.showToast('Фото должно быть в формате JPEG, PNG или WebP', 'danger');
      return;
    }
    if (file.size > PHOTO_MAX_MB * 1024 * 1024) {
      window.showToast(`Файл больше ${PHOTO_MAX_MB} МБ`, 'danger');
      return;
    }

    const formData = new FormData();
    formData.append('file', file);

    photoUploadBtn.disabled = true;
    try {
      const resp = await fetch(`/api/v1/employees/${editingId}/photo`, {
        method: 'POST',
        body: formData,
        headers: { 'X-CSRF-Token': API.csrfToken() },
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data.detail || 'Не удалось загрузить фото');

      if (currentEmployee) currentEmployee.photo = data;
      renderPhoto(currentEmployee);
      loadEmployees();
      window.showToast('Фото загружено', 'success');
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      photoUploadBtn.disabled = !editingId;
      if (photoInput) photoInput.value = '';
    }
  }

  window.openCreateEmployee = () => {
    editingId = null;
    currentEmployee = null;
    ModalHelper.setTitle(modalEl, 'Новый сотрудник');
    saveBtn.textContent = 'Создать';
    setEditOnlyTabs(false);
    resetModal();
    renderPhoto(null);
    ModalHelper.show(modalEl);
  };

  window.openEditEmployee = async (id) => {
    try {
      const emp = await API.get(`/api/v1/employees/${id}`);
      editingId = id;
      currentEmployee = emp;

      ModalHelper.setTitle(
        modalEl,
        `Редактирование: ${[emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ')}`
      );
      saveBtn.textContent = 'Сохранить';
      resetModal();
      renderPhoto(emp);

      const FIELDS = [
        'personnel_number', 'personal_card_number', 'last_name', 'first_name',
        'middle_name', 'hire_date', 'position_change_date', 'gender',
      ];
      FIELDS.forEach((f) => {
        const input = createForm.elements[f];
        if (!input) return;
        input.value = f.includes('_date') && emp[f] ? dateInputValue(emp[f]) : (emp[f] ?? '');
      });

      // Рост — список из сетки Положения, а не свободный ввод
      setEmployeeHeight(emp.height);

      createDeptSelect.value = emp.department_id ?? '';
      await loadPositionsForSelect(emp.department_id, emp.position_id);

      // Только теперь известна должность: вкладка выдач зависит от неё
      setEditOnlyTabs(true);

      versionInput.value = emp.version ?? '';

      for (const size of emp.ppe_sizes ?? []) {
        sizesBody.appendChild(await buildSizeRow(size.size_group_id, size.size_value));
      }
      renderIssues(emp);
      renderOnHand(emp);
      // Нормы грузятся запросом: рисуем, когда придут, — карточку не держим
      void renderNorms(emp);

      ModalHelper.show(modalEl);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Срок носки истёк — подсвечиваем, чтобы выдача была видна сразу
  function expiryCell(raw) {
    if (!raw) return '<span class="cell-muted">—</span>';
    const date = new Date(dateInputValue(raw));
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const expired = date < today;
    const cls = expired ? 'badge-soft badge-orange' : 'badge-soft badge-purple';
    const label = expired ? `истёк ${formatDateRu(raw)}` : formatDateRu(raw);
    return `<span class="${cls}">${escapeHtml(label)}</span>`;
  }

  // Рост приходит из сетки Положения. У старых записей там может стоять
  // значение вне сетки («180») — показываем его отдельным пунктом с пометкой,
  // чтобы было видно, что чинить: молча подменить значение нельзя.
  function setEmployeeHeight(value) {
    const select = createForm.elements['height'];
    if (!select) return;

    select.querySelectorAll('option[data-legacy]').forEach((option) => option.remove());

    const known = [...select.options].map((option) => option.value);
    if (value && !known.includes(value)) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = `${value} (вне сетки — выберите из списка)`;
      option.dataset.legacy = '1';
      select.appendChild(option);
    }

    select.value = value ?? '';
  }

  function renderIssues(emp) {
    const issues = emp.ppe_issues ?? emp.issues ?? [];
    issueById = new Map(issues.map((i) => [String(i.id), i]));

    if (!issues.length) {
      tableState(issuesBody, 6, 'Выдач пока нет');
      return;
    }

    issuesBody.innerHTML = issues.map((i) => `<tr>
          <td>${escapeHtml(i.ppe_item?.name ?? '—')}</td>
          <td>${escapeHtml(i.size_value ?? '—')}</td>
          <td>${escapeHtml(String(i.quantity ?? '—'))}</td>
          <td>${escapeHtml(formatDateRu(i.issue_date))}</td>
          <td>${expiryCell(i.expiry_date)}</td>
          <td class="col-actions">
            <button class="btn btn-icon" data-action="return-issue" data-id="${i.id}"
                    title="${escapeHtml(returnButtonTitle(i))}">
              <i class="bi bi-arrow-return-left"></i>
            </button>
            <button class="btn btn-icon btn-icon--danger" data-action="delete-issue"
                    data-id="${i.id}" title="Убрать выдачу">
              <i class="bi bi-trash"></i>
            </button>
          </td>
        </tr>`).join('');
  }

  // Вкладка «СИЗ в наличии»: что реально числится за сотрудником сейчас.
  // Считаем по остаткам (выдано − возвращено), а не по числу строк: полностью
  // возвращённые выдачи не показываем, а две выдачи одного СИЗ складываем
  // в одну строку — иначе «2 + 2» выглядели как две разные позиции.
  function groupOnHand(issues) {
    // Одна строка на наименование. Отдельно от renderOnHand, чтобы агрегацию
    // остатков можно было проверить без DOM: две выдачи по 2 — это 4,
    // а полностью возвращённая запись в список не попадает вовсе.
    const byItem = new Map();
    (issues ?? []).forEach((issue) => {
      if ((issueBalance(issue) ?? 1) <= 0) return;
      const key = issue.ppe_item_id;
      const row = byItem.get(key) ?? {
        name: issue.ppe_item?.name ?? '—',
        sizes: [],
        quantity: 0,
        unknown: false,
      };
      if (issue.size_value && !row.sizes.includes(String(issue.size_value))) {
        row.sizes.push(String(issue.size_value));
      }
      const balance = issueBalance(issue);
      if (balance === null) row.unknown = true;
      else row.quantity += balance;
      byItem.set(key, row);
    });
    return [...byItem.values()].sort((a, b) => a.name.localeCompare(b.name, 'ru'));
  }

  function renderOnHand(emp) {
    if (!onHandBody) return;
    const rows = groupOnHand(emp?.ppe_issues);
    if (!rows.length) {
      tableState(onHandBody, 3, 'СИЗ на руках нет');
      return;
    }
    // Даты выдачи и сроки здесь не показываем: это суммарный остаток по
    // наименованию, у него нет одной даты и одного срока. За ними — на
    // вкладку «Выданные СИЗ»
    onHandBody.innerHTML = rows.map((row) => `<tr>
          <td>${escapeHtml(row.name)}</td>
          <td>${escapeHtml(row.sizes.join(', ') || '—')}</td>
          <td>${escapeHtml(row.unknown ? '—' : String(row.quantity))}</td>
        </tr>`).join('');
  }

  // Вкладка «СИЗ по нормам»: что положено по должности и сколько уже на руках.
  // Норму показываем словами («2 пары на 1 год»), как в модалке выдачи.
  // Данные строки «СИЗ по нормам» — без HTML: правило «есть / не выдано /
  // просрочено» проверяется тестом, а разметка только собирает строку.
  function normRowModel(norm, item, emp) {
    const normQuantity = String(norm.quantity ?? '1').trim();
    const digits = FormHelper.digits(normQuantity, 3);
    const quantityText = formatQuantityRu(digits || normQuantity, item.unit?.name);
    const periodText = norm.wear_period_unit === 'до износа'
      ? 'до износа'
      : `на ${formatPeriodRu(norm.wear_period_value, norm.wear_period_unit)}`;

    const active = activeIssues(item.id);
    const today = todayIso();
    const allExpired = active.length > 0
      && active.every((i) => i.expiry_date && i.expiry_date < today);

    return {
      name: item.name,
      normText: `${quantityText} ${periodText}`,
      size: sizeFromCard(emp, item) ?? '—',
      onHand: onHandQuantity(item.id),
      state: !active.length ? 'none' : (allExpired ? 'expired' : 'ok'),
    };
  }

  const NORM_STATE_HTML = {
    none: '<span class="cell-muted">не выдано</span>',
    expired: '<span class="badge-soft badge-orange">просрочено</span>',
    ok: '<span class="badge-soft badge-purple">есть</span>',
  };

  async function renderNorms(emp) {
    if (!normsBody) return;
    if (!emp?.position_id) {
      tableState(normsBody, 5, 'У сотрудника не указана должность — нормы не заданы');
      return;
    }

    try {
      if (!allPpeItems) {
        allPpeItems = await API.get('/api/v1/ppe_items');
      }
      await loadNormsForEmployee(emp);
    } catch (err) {
      tableState(normsBody, 5, `Ошибка загрузки норм: ${err.message}`, { error: true });
      return;
    }

    if (!normByItem.size) {
      tableState(normsBody, 5, 'Для должности не заданы нормы выдачи');
      return;
    }

    const rows = [...normByItem.values()]
      .map((norm) => ({ norm, item: allPpeItems.find((i) => i.id === norm.ppe_item_id) }))
      .filter((row) => row.item)
      .sort((a, b) => a.item.name.localeCompare(b.item.name, 'ru'))
      .map(({ norm, item }) => normRowModel(norm, item, emp));

    normsBody.innerHTML = rows.map((row) => `<tr>
          <td>${escapeHtml(row.name)}</td>
          <td>${escapeHtml(row.normText)}</td>
          <td>${escapeHtml(row.size)}</td>
          <td>${escapeHtml(String(row.onHand))}</td>
          <td>${NORM_STATE_HTML[row.state]}</td>
        </tr>`).join('');
  }

  // Графы 7-10 карточки: что вернули и каким актом списали. Отдельной колонки
  // в таблице больше нет — она занимала пол-экрана, поэтому статус возврата
  // показывается в подсказке кнопки, а сами поля правятся в модалке.
  function returnSummary(issue) {
    const parts = [];
    if (issue.returned_date) {
      const qty = issue.returned_quantity ? ` (${issue.returned_quantity})` : '';
      parts.push(`возврат ${formatDateRu(issue.returned_date)}${qty}`);
    }
    if (issue.write_off_act_number) {
      const date = issue.write_off_act_date ? ` от ${formatDateRu(issue.write_off_act_date)}` : '';
      parts.push(`акт № ${issue.write_off_act_number}${date}`);
    }
    return parts.join('; ');
  }

  // Имя функции с суффиксом Button: иначе конфликт с `returnTitle` —
  // это DOM-элемент заголовка модалки (const в этой же области видимости)
  function returnButtonTitle(issue) {
    const summary = returnSummary(issue);
    return summary ? `Возврат и акт списания: ${summary}` : 'Возврат и акт списания';
  }

  // --- Выдача СИЗ -------------------------------------------------------
  const issueModalEl = document.getElementById('issueModal');
  const issueForm = document.getElementById('issue-form');
  const issueItemSelect = document.getElementById('issue-item');
  const issueSizeSelect = document.getElementById('issue-size');
  const issueSizeHint = document.getElementById('issue-size-hint');
  const issueNormHint = document.getElementById('issue-norm-hint');
  const issueQuantityInput = document.getElementById('issue-quantity');
  const issueQuantityHint = document.getElementById('issue-quantity-hint');
  const issueWarningEl = document.getElementById('issue-warning');
  const issueDateInput = document.getElementById('issue-date');
  const issueMethodWrap = document.getElementById('issue-method-wrap');
  const issueMethodSelect = document.getElementById('issue-method');

  let allPpeItems = null;
  let normByItem = new Map();

  // Справочник размеров по размерным группам. Размер выдаваемого СИЗ — это
  // список, а не ввод руками: ручной ввод давал «58 размер» мимо таблицы
  // размеров, и такие значения потом не совпадали с карточкой сотрудника.
  const sizesByGroup = new Map();

  // Нормы должности нужны, чтобы показать срок носки и подсказать размер
  async function loadNormsForEmployee(emp) {
    normByItem = new Map();
    if (!emp.position_id) return;
    try {
      const norms = await API.get(`/api/v1/position_ppe_norms/?position_id=${emp.position_id}`);
      norms.forEach((n) => normByItem.set(n.ppe_item_id, n));
    } catch (err) {
      // без норм выдача всё равно возможна
    }
  }

  // Графа 5 карточки заполняется только для дерматологических СИЗ: у
  // остальных там всегда «лично», и лишнее поле в форме только путало бы
  function toggleIssueMethod(item) {
    const isDermatological = /дерматолог/i.test(item?.function?.name ?? '');
    issueMethodWrap?.classList.toggle('d-none', !isDermatological);
    if (!isDermatological && issueMethodSelect) issueMethodSelect.value = '';
  }

  // Размер берём из карточки по размерной группе СИЗ
  function sizeFromCard(emp, item) {
    const groupId = item?.size_group_id;
    if (!groupId) return null;
    const size = (emp?.ppe_sizes ?? []).find((s) => s.size_group_id === groupId);
    return size?.size_value ?? null;
  }

  // Остаток по одной выдаче: выдано − возвращено. null — количество записано
  // не числом («2 пары»), тогда остаток неизвестен.
  function issueBalance(issue) {
    const issued = firstNumber(issue?.quantity);
    if (issued === null) return null;
    const returned = firstNumber(issue?.returned_quantity) ?? 0;
    return issued - returned;
  }

  // Выдачи этого СИЗ, которые ещё на руках: остаток больше нуля или неизвестен.
  // Именно они делают новую выдачу повторной.
  function activeIssues(itemId) {
    return (currentEmployee?.ppe_issues ?? []).filter(
      (i) => i.ppe_item_id === itemId && (issueBalance(i) ?? 1) > 0
    );
  }

  // Сколько всего этого СИЗ на руках (для подсказки и сравнения с нормой)
  function onHandQuantity(itemId) {
    return activeIssues(itemId).reduce((sum, i) => sum + (issueBalance(i) ?? 1), 0);
  }

  // Размеры размерной группы берём из справочника и запоминаем: при открытии
  // модалки сотрудник перебирает несколько СИЗ одной группы подряд.
  async function loadSizesForGroup(groupId) {
    if (!sizesByGroup.has(groupId)) {
      sizesByGroup.set(
        groupId,
        API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`).catch((err) => {
          // Ошибку не кэшируем: следующий выбор СИЗ должен повторить запрос
          sizesByGroup.delete(groupId);
          throw err;
        })
      );
    }
    return sizesByGroup.get(groupId);
  }

  // В справочнике размер может быть без указания пола — он подходит обоим
  function sizesForEmployeeGender(sizes) {
    const gender = currentEmployee?.gender ?? null;
    return gender ? sizes.filter((s) => !s.gender || s.gender === gender) : sizes;
  }

  // Список размеров выбранного СИЗ: значения из справочника его размерной
  // группы, а выбран по умолчанию тот, что записан в карточке сотрудника.
  async function fillSizeOptions(item) {
    issueSizeSelect.innerHTML = '<option value="">Загрузка…</option>';
    issueSizeSelect.disabled = true;
    issueSizeHint.textContent = '';

    const cardSize = sizeFromCard(currentEmployee, item);
    const group = item?.size_group ?? null;

    if (!item || !item.size_group_id) {
      issueSizeSelect.innerHTML = '<option value="">Не требуется</option>';
      issueSizeHint.textContent = item
        ? 'У этого СИЗ размерная группа не задана — размер не нужен'
        : '';
      return;
    }

    let sizes;
    try {
      sizes = sizesForEmployeeGender(await loadSizesForGroup(item.size_group_id));
    } catch (err) {
      issueSizeSelect.innerHTML = '<option value="">Не удалось загрузить</option>';
      issueSizeHint.textContent = 'Справочник размеров недоступен — размер не выбран';
      return;
    }

    // Размер из карточки мог быть задан до появления справочника и в него не
    // попасть. Тогда оставляем его вариантом: иначе подстановка молча терялась
    // и вместо своего размера сотрудник получал чужой из начала списка.
    const values = sizes.map((s) => s.size_value);
    if (cardSize && !values.includes(cardSize)) values.unshift(cardSize);

    if (!values.length) {
      issueSizeSelect.innerHTML = '<option value="">В группе нет размеров</option>';
      issueSizeHint.textContent = group
        ? `В группе «${group.name}» не заданы размеры — заполните справочник размеров`
        : 'В размерной группе этого СИЗ не заданы размеры';
      return;
    }

    issueSizeSelect.disabled = false;
    issueSizeSelect.innerHTML = '<option value="">Размер...</option>' + values.map((value) => {
      const size = sizes.find((s) => s.size_value === value);
      const genderMark = size?.gender === 'М' ? ' (М)' : size?.gender === 'Ж' ? ' (Ж)' : '';
      const fromCard = value === cardSize;
      return `<option value="${escapeHtml(value)}" ${fromCard ? 'selected' : ''}>` +
        `${escapeHtml(value)}${genderMark}${fromCard ? ' — из карточки' : ''}</option>`;
    }).join('');

    if (cardSize) {
      issueSizeHint.textContent = group
        ? `Подставлено из карточки сотрудника (группа «${group.name}»)`
        : 'Подставлено из карточки сотрудника';
    } else {
      issueSizeHint.textContent = group
        ? `В карточке нет размера для группы «${group.name}» — выберите из списка`
        : 'В карточке не указан размер — выберите из списка';
    }
  }

  // Сравнение количеств: «1 пара» и «1» — одно и то же, поэтому сравниваем
  // первое число. Если чисел нет («комплект») — сравниваем строки целиком.
  function firstNumber(raw) {
    const match = String(raw ?? '').replace(',', '.').match(/\d+(?:\.\d+)?/);
    return match ? Number(match[0]) : null;
  }

  // Предупреждения о расхождении выдачи с карточкой и нормой. Показываем, но
  // не запрещаем выдачу: обоснованное отклонение от нормы — рабочая ситуация,
  // а молчаливая запись «чего-нибудь» — ошибка учёта.
  function updateIssueWarnings() {
    if (!issueWarningEl) return;

    const itemId = Number(issueItemSelect?.value);
    const item = allPpeItems?.find((i) => i.id === itemId);
    const warnings = [];

    if (item) {
      const groupName = item.size_group?.name;
      const cardSize = sizeFromCard(currentEmployee, item);
      const chosenSize = issueSizeSelect?.value?.trim() ?? '';

      if (item.size_group_id && !cardSize) {
        warnings.push(groupName
          ? `В карточке сотрудника не указан размер для группы «${groupName}».`
          : 'В карточке сотрудника не указан размер для этой группы.');
      } else if (cardSize && chosenSize && chosenSize !== cardSize) {
        warnings.push(
          `Размер «${chosenSize}» не совпадает с размером из карточки сотрудника («${cardSize}»).`
        );
      }

      const active = activeIssues(itemId);
      const onHand = onHandQuantity(itemId);
      if (active.length) {
        const first = active[0];
        const until = first.expiry_date ? `, до ${formatDateRu(first.expiry_date)}` : '';
        warnings.push(
          `У сотрудника уже есть это СИЗ: на руках ${onHand} `
          + `(записей ${active.length}, первая от ${formatDateRu(first.issue_date)}${until}). `
          + 'Новая выдача будет повторной.'
        );
      }

      const norm = normByItem.get(itemId);
      const quantity = issueQuantityInput?.value?.trim() ?? '';
      if (norm && quantity) {
        const normQuantity = String(norm.quantity ?? '1').trim();
        const left = firstNumber(quantity);
        const right = firstNumber(normQuantity);
        const same = left !== null && right !== null
          ? left === right
          : quantity === normQuantity;
        if (!same) {
          warnings.push(
            `Количество «${quantity}» не совпадает с нормой для должности («${normQuantity}»).`
          );
        }
        // Норма — на период. Если на руках уже есть, новая выдача выходит за неё
        const add = firstNumber(quantity);
        if (right !== null && add !== null && onHand + add > right) {
          warnings.push(
            `С учётом остатка получится ${onHand + add} при норме ${right} — выдача выходит за норму.`
          );
        }
      }
    }

    if (!warnings.length) {
      issueWarningEl.classList.add('d-none');
      issueWarningEl.innerHTML = '';
      return;
    }

    issueWarningEl.classList.remove('d-none');
    issueWarningEl.innerHTML = warnings.map((w) => `<div>${escapeHtml(w)}</div>`).join('');
  }

  async function openIssueModal() {
    if (!editingId) return;

    if (!allPpeItems) {
      try {
        allPpeItems = await API.get('/api/v1/ppe_items');
      } catch (err) {
        window.showToast(`Ошибка загрузки СИЗ: ${err.message}`, 'danger');
        return;
      }
    }

    // Выдавать можно только то, что положено по нормам должности.
    // Список всех СИЗ позволял выдать что угодно мимо нормы.
    const normItems = [...normByItem.values()]
      .map((n) => {
        const item = allPpeItems.find((i) => i.id === n.ppe_item_id);
        return item ? { item, norm: n } : null;
      })
      .filter(Boolean)
      .sort((a, b) => a.item.name.localeCompare(b.item.name, 'ru'));

    if (!normItems.length) {
      const reason = currentEmployee?.position_id
        ? 'для должности не заданы нормы выдачи'
        : 'у сотрудника не указана должность';
      issueItemSelect.innerHTML = `<option value="">Нет норм: ${escapeHtml(reason)}</option>`;
      issueItemSelect.disabled = true;
      document.getElementById('issue-submit').disabled = true;
      // Поля выдачи остаются пустыми: подставлять размер и количество не из чего
      issueSizeSelect.innerHTML = '<option value="">Нет норм</option>';
      issueSizeSelect.disabled = true;
      issueSizeHint.textContent = '';
      issueQuantityHint.textContent = '';
      issueNormHint.textContent = '';
      toggleIssueMethod(null);
      updateIssueWarnings();
      ModalHelper.show(issueModalEl);
      return;
    }

    issueItemSelect.disabled = false;
    document.getElementById('issue-submit').disabled = false;

    issueItemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' +
      normItems.map(({ item, norm }) => {
        const onHand = onHandQuantity(item.id);
        const total = norm.quantity ?? '1';
        // Показываем остаток, а не число строк: две записи «2» — это 4 на руках
        const mark = onHand ? ` — на руках ${onHand} из ${total}` : '';
        return `<option value="${item.id}">${escapeHtml(item.name)}${escapeHtml(mark)}</option>`;
      }).join('');

    issueForm.reset();
    issueQuantityInput.value = '1';
    issueQuantityHint.textContent = '';
    issueDateInput.value = todayIso();
    issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ</option>';
    issueSizeSelect.disabled = true;
    issueSizeHint.textContent = '';
    issueNormHint.textContent = '';
    issueMethodWrap?.classList.add('d-none');
    if (issueMethodSelect) issueMethodSelect.value = '';
    updateIssueWarnings();

    ModalHelper.show(issueModalEl);
  }

  // При выборе СИЗ: размер — списком из справочника с подстановкой размера из
  // карточки сотрудника, количество — из нормы выдачи для должности.
  issueItemSelect?.addEventListener('change', async () => {
    const itemId = Number(issueItemSelect.value);
    const item = allPpeItems?.find((i) => i.id === itemId);
    const norm = normByItem.get(itemId);

    issueNormHint.textContent = '';
    issueQuantityHint.textContent = '';

    if (!item) {
      issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ</option>';
      issueSizeSelect.disabled = true;
      issueSizeHint.textContent = '';
      toggleIssueMethod(null);
      updateIssueWarnings();
      return;
    }

    if (norm) {
      const normQuantity = String(norm.quantity ?? '1').trim();
      // В норме количество может быть записано словами («2 пары»), а в поле
      // допустимы только цифры — берём число и предупреждаем, что подставили
      const digits = FormHelper.digits(normQuantity, 3);
      // Гуманизация: «2 пары на 1 год» вместо «1 год, количество 2».
      // Единица измерения — из справочника единиц (поле СИЗ), срок склоняется.
      const quantityText = formatQuantityRu(digits || normQuantity, item?.unit?.name);
      const periodText = norm.wear_period_unit === 'до износа'
        ? 'до износа'
        : `на ${formatPeriodRu(norm.wear_period_value, norm.wear_period_unit)}`;
      issueNormHint.textContent = `По норме: ${quantityText} ${periodText}`;
      issueQuantityInput.value = digits || '1';
      issueQuantityHint.textContent = digits === normQuantity
        ? 'Подставлено из нормы выдачи для должности'
        : `В норме указано «${normQuantity}» — подставлено ${digits || '1'}, проверьте количество`;
    } else {
      issueQuantityHint.textContent = 'Для должности норма не задана — количество не подставлено';
    }

    await fillSizeOptions(item);
    toggleIssueMethod(item);
    updateIssueWarnings();
    window.FormValidation.refresh(issueForm);
  });

  // Размер и количество после подстановки можно изменить — тогда предупреждение
  // должно появиться или исчезнуть сразу, без повторного выбора СИЗ
  issueSizeSelect?.addEventListener('change', updateIssueWarnings);
  issueQuantityInput?.addEventListener('input', updateIssueWarnings);

  issueForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!editingId) return;

    const payload = {
      employee_id: editingId,
      ppe_item_id: Number(issueItemSelect.value),
      issue_date: issueDateInput.value,
      quantity: issueForm.elements['quantity'].value.trim() || '1',
      size_value: issueSizeSelect.value.trim() || null,
      // «дозатор» бывает только у дерматологических СИЗ — поле скрыто
      // у остальных, и в запрос уходит null
      issue_method: issueMethodWrap?.classList.contains('d-none')
        ? null
        : (issueMethodSelect?.value || null),
    };

    // Повторная выдача того же СИЗ — только после явного подтверждения.
    // Раньше можно было выдать «ботинки, 2» сколько угодно раз, и в карточке
    // появлялись две одинаковые строки на одну дату.
    const active = activeIssues(payload.ppe_item_id);
    if (active.length) {
      const first = active[0];
      const onHand = onHandQuantity(payload.ppe_item_id);
      const until = first.expiry_date ? `, действует до ${formatDateRu(first.expiry_date)}` : '';
      const question = `У сотрудника уже есть это СИЗ: на руках ${onHand} `
        + `(записей ${active.length}, первая выдана ${formatDateRu(first.issue_date)}${until}).

`
        + `Выдать ещё ${payload.quantity}?`;
      if (!window.confirm(question)) return;
      // Сервер тоже проверяет дубль: без force он ответит 409
      payload.force = true;
    }

    await FormHelper.send(issueForm, async () => {
      await API.post('/api/v1/employee_ppe_issues/', payload);
      window.showToast('СИЗ выдан', 'success');
      ModalHelper.hide(issueModalEl);
      await reloadEmployee();
    }, {
      button: document.getElementById('issue-submit'),
      payload,
      validate: (data) => (data.ppe_item_id ? null : 'Выберите наименование СИЗ'),
    });
  });

  // Перезапрос карточки: срок носки считает сервер, клиенту его не вычислить
  async function reloadEmployee() {
    if (!editingId) return;
    try {
      const emp = await API.get(`/api/v1/employees/${editingId}`);
      currentEmployee = emp;
      renderIssues(emp);
      renderOnHand(emp);
      void renderNorms(emp);
      renderPhoto(emp);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  }

  issuesBody?.addEventListener('click', async (event) => {
    const returnBtn = event.target.closest('[data-action="return-issue"]');
    if (returnBtn) {
      openReturnModal(issueById.get(returnBtn.dataset.id));
      return;
    }

    const btn = event.target.closest('[data-action="delete-issue"]');
    if (!btn) return;
    if (!confirm('Убрать выдачу из карточки?')) return;

    try {
      await API.request(`/api/v1/employee_ppe_issues/${btn.dataset.id}`, { method: 'DELETE' });
      window.showToast('Выдача убрана', 'success');
      await reloadEmployee();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  // --- Возврат и акт списания (графы 7-10 карточки) ---------------------
  const returnModalEl = document.getElementById('returnModal');
  const returnForm = document.getElementById('return-form');
  const returnTitle = document.getElementById('return-issue-title');
  let returnIssue = null;

  function openReturnModal(issue) {
    if (!issue || !returnForm) return;
    returnIssue = issue;

    const name = issue.ppe_item?.name ?? 'Выдача СИЗ';
    const size = issue.size_value ? `, размер ${issue.size_value}` : '';
    returnTitle.textContent = `${name}${size} — выдано ${formatDateRu(issue.issue_date)}`;

    const fields = returnForm.elements;
    fields['returned_date'].value = dateInputValue(issue.returned_date);
    // Старая запись могла хранить нечисловое количество («-5», «2 пары») —
    // в поле показываем только цифры, иначе маска молча пропускала бы минус
    fields['returned_quantity'].value = FormHelper.digits(issue.returned_quantity, 3);
    fields['write_off_act_date'].value = dateInputValue(issue.write_off_act_date);
    fields['write_off_act_number'].value = issue.write_off_act_number ?? '';

    updateReturnHint(issue);

    window.FormValidation.refresh(returnForm);
    ModalHelper.show(returnModalEl);
  }

  // Остаток = выдано − возвращено. Показываем его прямо в модалке: иначе
  // «выдано 2, возвращено 6» замечают уже после сохранения
  function updateReturnHint(issue, returnedValue) {
    const hint = document.getElementById('return-quantity-hint');
    if (!hint) return;

    const returned = returnedValue === undefined ? issue.returned_quantity : returnedValue;
    const { text, isError } = Quantity.describeReturn(issue.quantity, returned);

    hint.textContent = text;
    hint.classList.toggle('text-danger', isError);
  }

  // Остаток пересчитывается на лету: сразу видно, сколько останется на руках
  returnForm?.elements['returned_quantity']?.addEventListener('input', (event) => {
    if (!returnIssue) return;
    // Чистим значение здесь же: маска подключена отдельным слушателем и
    // сработает после этого, а подсказка должна видеть уже только цифры
    event.target.value = FormHelper.digits(event.target.value, 3);
    updateReturnHint(returnIssue, event.target.value);
  });

  returnForm?.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!returnIssue) return;

    const fields = returnForm.elements;
    const returnedRaw = fields['returned_quantity'].value.trim();

    // Остаток не должен уйти в минус: проверяем до запроса, чтобы не показывать
    // ошибку сервера там, где можно сказать точнее
    if (returnedRaw) {
      // Разбор и правило остатка — в Quantity: та же логика, что в подсказке
      const { isError } = Quantity.describeReturn(returnIssue.quantity, returnedRaw);
      const issued = Quantity.parse(returnIssue.quantity);
      const returned = Quantity.parse(returnedRaw);

      if (!Number.isFinite(issued) || issued <= 0) {
        window.showToast(
          `Количество выдачи «${returnIssue.quantity}» не число — остаток не проверить`,
          'danger'
        );
        return;
      }
      if (isError) {
        window.showToast(
          !Number.isFinite(returned) || returned <= 0
            ? 'Количество возврата — только цифры и больше нуля'
            : `Возврат больше выдачи: выдано ${issued}, возвращают ${returned}. Остаток не может быть отрицательным`,
          'danger'
        );
        return;
      }
    }

    const payload = {
      returned_date: fields['returned_date'].value || null,
      returned_quantity: returnedRaw || null,
      write_off_act_date: fields['write_off_act_date'].value || null,
      write_off_act_number: fields['write_off_act_number'].value.trim() || null,
      version: Number(returnIssue.version),
    };

    await FormHelper.send(returnForm, async () => {
      await API.put(`/api/v1/employee_ppe_issues/${returnIssue.id}`, payload);
      window.showToast('Возврат сохранён', 'success');
      ModalHelper.hide(returnModalEl);
      await reloadEmployee();
    }, {
      button: document.getElementById('return-submit'),
      payload,
      onConflict: () => window.showToast('Запись изменилась, откройте её заново', 'warning'),
    });
  });

  document.getElementById('emp-add-issue')?.addEventListener('click', () => {
    // Нормы грузим один раз на открытие карточки
    Promise.resolve(currentEmployee ? loadNormsForEmployee(currentEmployee) : null)
      .then(openIssueModal);
  });

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
      TabHelper.show('#employeeModalTabs [data-bs-target="#emp-tab-main"]');
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
      TabHelper.show('#employeeModalTabs [data-bs-target="#emp-tab-sizes"]');
      return;
    }

    const payload = FormHelper.serialize(createForm);
    payload.department_id = Number(payload.department_id);
    payload.position_id = Number(payload.position_id);
    if (!payload.hire_date) payload.hire_date = null;
    if (!payload.position_change_date) payload.position_change_date = null;
    payload.ppe_sizes = ppeSizes;

    await FormHelper.send(createForm, async (payload) => {
      if (editingId) {
        payload.version = Number(versionInput.value);
        await API.put(`/api/v1/employees/${editingId}`, payload);
        window.showToast('Сотрудник сохранён', 'success');
      } else {
        await API.post('/api/v1/employees/', payload);
        window.showToast('Сотрудник создан', 'success');
      }
    }, {
      button: saveBtn,
      payload,
      onSuccess: () => {
        ModalHelper.hide(modalEl);
        loadEmployees();
      },
    });
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
    // Возврат оформили в другой вкладке — перечитываем выдачи открытой карточки
    if (data.event === 'issue_updated' && data.employee_id === editingId) {
      reloadEmployee();
    }
    // Справочник размеров поправили в соседней вкладке: кэши устарели, а в
    // открытой модалке выдачи остались бы прежние варианты размера
    if (data.event === 'size_group_updated' || data.event === 'size_updated') {
      allSizeGroupsCache = null;
      sizesByGroup.clear();
      const issueOpen = issueModalEl?.classList.contains('show');
      const chosenItem = allPpeItems?.find((i) => i.id === Number(issueItemSelect?.value));
      if (issueOpen && chosenItem) fillSizeOptions(chosenItem);
    }
  });

  // Количество — только цифры, не больше трёх: «-5» и «2,5» ломали остаток.
  // Подключаем по id: это то же поле, что и name="returned_quantity", но
  // ссылка не зависит от резолва элементов формы
  FormHelper.onlyDigits(issueQuantityInput, 3);
  FormHelper.onlyDigits(document.getElementById('return-quantity'), 3);

  // Кнопки фото: выбор файла и удаление. Загрузка идёт отдельным fetch с
  // FormData — API.request рассчитан на JSON.
  photoUploadBtn?.addEventListener('click', () => photoInput?.click());
  photoInput?.addEventListener('change', () => uploadPhoto(photoInput.files?.[0]));

  // Файл мог не приехать вместе с томом: сервер отвечает 404, и браузер нарисовал
  // бы «битую» картинку с alt-текстом. Показываем силуэт и говорим причину.
  photoPreview?.addEventListener('error', () => {
    photoPreview.classList.add('d-none');
    photoPreview.removeAttribute('src');
    photoEmpty?.classList.remove('d-none');
    if (photoHint) {
      photoHint.textContent = 'Файл фото не найден на сервере — загрузите заново';
      photoHint.classList.add('text-danger');
    }
  });

  photoDeleteBtn?.addEventListener('click', async () => {
    if (!editingId || !confirm('Удалить фото сотрудника?')) return;

    photoDeleteBtn.disabled = true;
    try {
      const resp = await fetch(`/api/v1/employees/${editingId}/photo`, {
        method: 'DELETE',
        headers: { 'X-CSRF-Token': API.csrfToken() },
      });
      if (!resp.ok) {
        const data = await resp.json().catch(() => ({}));
        throw new Error(data.detail || 'Не удалось удалить фото');
      }
      if (currentEmployee) currentEmployee.photo = null;
      renderPhoto(currentEmployee);
      loadEmployees();
      window.showToast('Фото удалено', 'success');
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      photoDeleteBtn.disabled = false;
    }
  });

  loadDepartmentsForSelect();
  loadEmployees();
})();

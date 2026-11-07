(() => {
  const tbody = document.querySelector('#departments-table tbody');
  const createForm = document.getElementById('create-form');
  const createParentSelect = document.getElementById('create-parent');

  let allDepartments = [];

  // Функция для построения иерархического списка
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

  const searchInput = document.getElementById('search-input');

  async function loadDepartments() {
    try {
      allDepartments = await API.get('/api/v1/departments');
      const hierarchy = buildHierarchy(allDepartments);
      applyFilter(hierarchy);

      // Заполняем выпадающий список для создания (тоже иерархически)
      if (createParentSelect) {
        createParentSelect.innerHTML = '<option value="">Нет (корневое)</option>' +
          hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tableState(tbody, 3, `Ошибка: ${err.message}`, { error: true });
    }
  }


  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  // Поиск по названию оставляет найденные подразделения и их предков,
  // иначе у найденного элемента не видно, к чему он относится
  function filterHierarchy(hierarchy, term) {
    if (!term) return hierarchy;

    const byId = new Map(hierarchy.map((d) => [d.id, d]));
    const keep = new Set();

    hierarchy.forEach((d) => {
      if (d.name.toLowerCase().includes(term)) {
        let current = d;
        while (current) {
          keep.add(current.id);
          current = current.parent_id ? byId.get(current.parent_id) : null;
        }
      }
    });

    return hierarchy.filter((d) => keep.has(d.id));
  }

  function applyFilter(hierarchy) {
    const term = searchInput ? searchInput.value.trim().toLowerCase() : '';
    renderTable(filterHierarchy(hierarchy, term));
  }

  if (searchInput) {
    searchInput.addEventListener('input', () => {
      applyFilter(buildHierarchy(allDepartments));
    });
  }

  function renderTable(hierarchy) {
    if (!hierarchy.length) {
      tableState(tbody, 3, 'Подразделений пока нет');
      return;
    }

    // Находим родителя для каждого элемента (для отображения в колонке "Вышестоящее")
    const deptMap = {};
    hierarchy.forEach(d => { deptMap[d.id] = d; });

    tbody.innerHTML = hierarchy.map(d => {
      const parentName = d.parent_id && deptMap[d.parent_id] ? deptMap[d.parent_id].name : '—';
      const fullName = escapeHtml(d.name);
      const shortName = escapeHtml(truncate(d.name, 50));
      const indent = '↳ '.repeat(d.level);

      return `
      <tr data-dept-id="${d.id}">
        <td title="${fullName}">${indent}${shortName}</td>
        <td class="cell-muted">${escapeHtml(parentName)}</td>
        <td class="col-actions">
          <button class="btn btn-icon js-edit-dept" data-id="${d.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger js-delete-dept" data-id="${d.id}" data-name="${fullName}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  // Имя передаём через data-атрибут: в onclick оно ломалась на кавычках
  tbody.addEventListener('click', (event) => {
    const del = event.target.closest('.js-delete-dept');
    if (del) {
      window.deleteDept(Number(del.dataset.id), del.dataset.name);
      return;
    }
    const edit = event.target.closest('.js-edit-dept');
    if (edit) window.openEditModal(Number(edit.dataset.id));
  });

  const modalEl = document.getElementById('createModal');
  const modalTitle = modalEl.querySelector('.modal-title');
  const submitBtn = modalEl.querySelector('button[type="submit"]');
  const versionInput = document.getElementById('dept-version');

  let editingId = null;

  // Открытие модалки в режиме создания
  function openCreateModal() {
    editingId = null;
    modalTitle.textContent = 'Новое подразделение';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    if (versionInput) versionInput.value = '';
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
  }

  // Открытие модалки в режиме редактирования: данные берём из уже
  // загруженного дерева, лишний запрос не нужен
  window.openEditModal = (id) => {
    const dept = allDepartments.find((d) => d.id === id);
    if (!dept) {
      window.showToast('Подразделение не найдено', 'danger');
      return;
    }

    editingId = id;
    modalTitle.textContent = 'Редактирование подразделения';
    submitBtn.textContent = 'Сохранить';

    createForm.elements['name'].value = dept.name ?? '';
    createForm.elements['parent_id'].value = dept.parent_id ?? '';
    if (versionInput) versionInput.value = dept.version ?? '';

    // Себя и потомков нельзя выбрать родителем — иначе получится цикл
    const forbidden = new Set([id, ...collectDescendantIds(id)]);
    Array.from(createForm.elements['parent_id'].options).forEach((opt) => {
      opt.disabled = opt.value !== '' && forbidden.has(Number(opt.value));
    });

    bootstrap.Modal.getOrCreateInstance(modalEl).show();
  };

  function collectDescendantIds(rootId) {
    const result = [];
    const stack = [rootId];
    while (stack.length) {
      const current = stack.pop();
      allDepartments
        .filter((d) => d.parent_id === current)
        .forEach((child) => {
          result.push(child.id);
          stack.push(child.id);
        });
    }
    return result;
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.parent_id = payload.parent_id ? Number(payload.parent_id) : null;

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      if (editingId) {
        payload.version = Number(versionInput.value);
        await API.put(`/api/v1/departments/${editingId}`, payload);
        window.showToast('Подразделение сохранено', 'success');
      } else {
        await API.post('/api/v1/departments/', payload);
        window.showToast('Подразделение создано', 'success');
      }
      bootstrap.Modal.getOrCreateInstance(modalEl).hide();
      createForm.reset();
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

  window.deleteDept = async (id, name) => {
    if (!confirm(`Удалить подразделение "${name}"?`)) return;
    try {
      await API.request(`/api/v1/departments/${id}`, { method: 'DELETE' });
      window.showToast('Подразделение удалено', 'success');
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'department_updated') loadDepartments();
  });

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  loadDepartments();
})();

(() => {
  const tbody = document.querySelector('#positions-table tbody');
  const createForm = document.getElementById('create-form');
  const createDeptSelect = document.getElementById('create-dept');
  const searchInput = document.getElementById('search-input');

  onRowAction(tbody, {
    delete: (id, name) => window.deletePos(id, name),
    edit: (id) => window.openEditModal(id),
  });

  let allPositions = [];
  let allDepartments = [];

  // Функция для построения полного пути к подразделению
  function buildDeptPath(deptId, depts) {
    if (!deptId) return '';
    const dept = depts.find(d => d.id === deptId);
    if (!dept) return '';
    const parentPath = dept.parent_id ? buildDeptPath(dept.parent_id, depts) : '';
    return parentPath ? `${parentPath} / ${dept.name}` : dept.name;
  }

  const PAGE_SIZE = 20;
  let currentPage = 1;
  let searchTerm = '';
  let searchTimer = null;

  async function loadData(page = currentPage) {
    currentPage = page;
    try {
      // Подразделения нужны целиком: из них строится путь и список в модалке
      allDepartments = await API.get('/api/v1/departments');

      const params = new URLSearchParams({
        paginated: 'true',
        page: String(currentPage),
        page_size: String(PAGE_SIZE),
      });
      if (searchTerm) params.set('search', searchTerm);

      const data = await API.get(`/api/v1/positions/?${params.toString()}`);
      allPositions = data.items;

      // Заполняем выпадающий список подразделений в модалке
      if (createDeptSelect) {
        const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
        createDeptSelect.innerHTML = '<option value="">Выберите подразделение...</option>' +
          sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
      }

      if (!data.items.length && data.total > 0 && currentPage > 1) {
        return loadData(currentPage - 1);
      }

      renderTable(data.items);
      Pager.render(document.getElementById('pager'), data, loadData);
    } catch (err) {
      tableState(tbody, 3, `Ошибка: ${err.message}`, { error: true });
    }
  }

  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        searchTerm = e.target.value.trim();
        loadData(1);
      }, 300);
    });
  }

  
  function truncateStart(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return '...' + str.slice(-maxLength);
  }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function renderTable(positions) {
    if (!positions.length) {
      tableState(tbody, 3, 'Должностей пока нет');
      return;
    }
    tbody.innerHTML = positions.map(p => {
      // Строим полный путь к подразделению
      const deptPath = buildDeptPath(p.department_id, allDepartments);
      const fullName = escapeHtml(p.name);
      const shortName = escapeHtml(truncate(p.name, 60));
      const shortDeptPath = escapeHtml(truncateStart(deptPath, 80));
      
      return `
      <tr data-pos-id="${p.id}">
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1" title="${escapeHtml(deptPath)}">
          <span class="badge-soft badge-purple">${shortDeptPath || '—'}</span>
        </td>
        <td class="col-actions">
          <button class="btn btn-icon" data-action="edit" data-id="${p.id}" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${p.id}" data-name="${fullName}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  const modalEl = document.getElementById('createModal');
  const modalTitle = modalEl.querySelector('.modal-title');
  const submitBtn = modalEl.querySelector('button[type="submit"]');
  const versionInput = document.getElementById('pos-version');

  let editingId = null;

  function openCreateModal() {
    editingId = null;
    modalTitle.textContent = 'Новая должность';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    if (versionInput) versionInput.value = '';
    bootstrap.Modal.getOrCreateInstance(modalEl).show();
  }

  window.openEditModal = async (id) => {
    try {
      // Значения и версию берём из API: строка может быть не на текущей странице
      const pos = await API.get(`/api/v1/positions/${id}`);
      editingId = id;
      modalTitle.textContent = 'Редактирование должности';
      submitBtn.textContent = 'Сохранить';

      createForm.elements['name'].value = pos.name ?? '';
      createForm.elements['department_id'].value = pos.department_id ?? '';
      if (versionInput) versionInput.value = pos.version ?? '';

      bootstrap.Modal.getOrCreateInstance(modalEl).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.department_id = Number(payload.department_id);

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      if (editingId) {
        payload.version = Number(versionInput.value);
        await API.put(`/api/v1/positions/${editingId}`, payload);
        window.showToast('Должность сохранена', 'success');
      } else {
        await API.post('/api/v1/positions/', payload);
        window.showToast('Должность создана', 'success');
      }
      bootstrap.Modal.getOrCreateInstance(modalEl).hide();
      createForm.reset();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      window.FormValidation.refresh();
    }
  });

  window.deletePos = async (id, name) => {
    if (!confirm(`Удалить должность "${name}"?`)) return;
    try {
      await API.request(`/api/v1/positions/${id}`, { method: 'DELETE' });
      window.showToast('Должность удалена', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'position_updated') loadData();
  });

  loadData();
})();

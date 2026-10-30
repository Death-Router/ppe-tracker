#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем шаблон списка СИЗ (компактная панель)..."

cat > app/templates/ppe_items/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Наименования СИЗ</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<!-- Панель фильтров и массовых действий -->
<div class="d-flex align-items-center gap-2 mb-3 flex-wrap">
    <div class="input-group flex-grow-1" style="min-width: 200px; max-width: 300px;">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    
    <select class="form-select" id="filter-function" style="width: auto;">
        <option value="">Все функции</option>
    </select>
    
    <select class="form-select" id="filter-size-group" style="width: auto;">
        <option value="">Все размерные группы</option>
    </select>

    <div class="ms-auto d-flex gap-2">
        <span id="selected-count" class="align-self-center fw-bold me-2 d-none">Выбрано: <span>0</span></span>
        <button id="btn-bulk-edit" class="btn btn-outline-primary" disabled onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>
        <button id="btn-bulk-delete" class="btn btn-outline-danger" disabled onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>
    </div>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="items-table">
            <thead class="bg-brand-orange">
            <tr>
                <th style="width: 40px;"><input type="checkbox" id="select-all"></th>
                <th>Наименование</th>
                <th>Функция / Группа</th>
                <th class="text-end">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="4" class="text-center text-muted py-4">Загрузка…</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Модалка создания -->
<div class="modal fade" id="createModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="create-form">
        <div class="modal-header">
          <h5 class="modal-title">Новое наименование СИЗ</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Наименование <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="255">
          </div>
          <div class="mb-3">
            <label class="form-label">Функция СИЗ</label>
            <select class="form-select" name="function_id" id="create-function">
                <option value="">Не указана</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">Размерная группа</label>
            <select class="form-select" name="size_group_id" id="create-size-group">
                <option value="">Не указана</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">Единица измерения</label>
            <select class="form-select" name="unit_id" id="create-unit">
                <option value="">Не указана</option>
            </select>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-primary">Создать</button>
        </div>
      </form>
    </div>
  </div>
</div>

<!-- Модалка массового редактирования -->
<div class="modal fade" id="bulkEditModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">Массовое редактирование (выбрано <span id="bulk-count">0</span>)</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
      </div>
      <div class="modal-body">
        <p class="text-muted small">Оставьте поле пустым, чтобы не изменять его.</p>
        <div class="mb-3">
            <label class="form-label">Функция СИЗ</label>
            <select class="form-select" id="bulk-function">
                <option value="">Не изменять</option>
            </select>
        </div>
        <div class="mb-3">
            <label class="form-label">Размерная группа</label>
            <select class="form-select" id="bulk-size-group">
                <option value="">Не изменять</option>
            </select>
        </div>
        <div class="mb-3">
            <label class="form-label">Единица измерения</label>
            <select class="form-select" id="bulk-unit">
                <option value="">Не изменять</option>
            </select>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>
        <button type="button" class="btn btn-primary" onclick="applyBulkEdit()">Применить</button>
      </div>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/ppe_items_list.js') }}"></script>
{% endblock %}
EOF

echo "📝 Обновляем JS для компактной панели..."

cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createFunctionSelect = document.getElementById('create-function');
  const createSizeGroupSelect = document.getElementById('create-size-group');
  const createUnitSelect = document.getElementById('create-unit');
  const searchInput = document.getElementById('search-input');
  const filterFunction = document.getElementById('filter-function');
  const filterSizeGroup = document.getElementById('filter-size-group');
  const selectAllCheckbox = document.getElementById('select-all');
  const selectedCountSpan = document.getElementById('selected-count');
  const btnBulkEdit = document.getElementById('btn-bulk-edit');
  const btnBulkDelete = document.getElementById('btn-bulk-delete');

  // Элементы модалки массового редактирования
  const bulkEditModal = new bootstrap.Modal(document.getElementById('bulkEditModal'));
  const bulkFunctionSelect = document.getElementById('bulk-function');
  const bulkSizeGroupSelect = document.getElementById('bulk-size-group');
  const bulkUnitSelect = document.getElementById('bulk-unit');
  const bulkCountSpan = document.getElementById('bulk-count');

  let allItems = [];
  let selectedIds = new Set();

  async function loadItems() {
    try {
      allItems = await API.get('/api/v1/ppe_items');
      filterItems();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      const groups = await API.get('/api/v1/ppe_size_groups');
      const units = await API.get('/api/v1/units');

      // Заполняем фильтры
      if (filterFunction) {
        filterFunction.innerHTML = '<option value="">Все функции</option>' +
          functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      }
      if (filterSizeGroup) {
        filterSizeGroup.innerHTML = '<option value="">Все размерные группы</option>' +
          groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      }

      // Заполняем селекты создания
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      createUnitSelect.innerHTML = '<option value="">Не указана</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');

      // Заполняем селекты массового редактирования
      bulkFunctionSelect.innerHTML = '<option value="">Не изменять</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      bulkSizeGroupSelect.innerHTML = '<option value="">Не изменять</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      bulkUnitSelect.innerHTML = '<option value="">Не изменять</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');

    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterItems() {
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const funcId = filterFunction ? Number(filterFunction.value) : null;
    const groupId = filterSizeGroup ? Number(filterSizeGroup.value) : null;

    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.function?.name || '').toLowerCase().includes(searchTerm) ||
        (item.size_group?.name || '').toLowerCase().includes(searchTerm)
      );
    }
    if (funcId) filtered = filtered.filter(item => item.function_id === funcId);
    if (groupId) filtered = filtered.filter(item => item.size_group_id === groupId);

    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));
    renderTable(filtered);
  }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => {
      const fullName = escapeHtml(i.name);
      const shortName = escapeHtml(truncate(i.name, 60));
      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">
        <td class="py-1">
          <input type="checkbox" class="item-checkbox" value="${i.id}" ${isChecked} onchange="toggleSelection(${i.id}, this.checked)">
        </td>
        <td class="py-1" title="${fullName}">${shortName}</td>
        <td class="py-1">
          <span class="badge bg-secondary me-1">${escapeHtml(i.function?.name ?? '—')}</span>
          <span class="badge bg-info">${escapeHtml(i.size_group?.name ?? '—')}</span>
        </td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteItem(${i.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
    updateBulkPanel();
  }

  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
  };

  function updateBulkPanel() {
    const count = selectedIds.size;
    if (count > 0) {
      selectedCountSpan.classList.remove('d-none');
      selectedCountSpan.querySelector('span').textContent = count;
      btnBulkEdit.disabled = false;
      btnBulkDelete.disabled = false;
    } else {
      selectedCountSpan.classList.add('d-none');
      btnBulkEdit.disabled = true;
      btnBulkDelete.disabled = true;
      selectAllCheckbox.checked = false;
    }
  }

  window.openBulkEditModal = () => {
    if (!selectedIds.size) return;
    bulkCountSpan.textContent = selectedIds.size;
    bulkFunctionSelect.value = '';
    bulkSizeGroupSelect.value = '';
    bulkUnitSelect.value = '';
    bulkEditModal.show();
  };

  window.applyBulkEdit = async () => {
    const funcId = bulkFunctionSelect.value;
    const groupId = bulkSizeGroupSelect.value;
    const unitId = bulkUnitSelect.value;

    if (!funcId && !groupId && !unitId) {
      window.showToast('Выберите хотя бы одно поле для изменения', 'warning');
      return;
    }

    try {
      await API.request('/api/v1/ppe_items/bulk', {
        method: 'PATCH',
        body: JSON.stringify({
          ids: Array.from(selectedIds),
          function_id: funcId ? Number(funcId) : null,
          size_group_id: groupId ? Number(groupId) : null,
          unit_id: unitId ? Number(unitId) : null
        })
      });
      window.showToast('Выбранные СИЗ обновлены', 'success');
      bulkEditModal.hide();
      selectedIds.clear();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  window.bulkDelete = async () => {
    if (!selectedIds.size) return;
    if (!confirm(`Удалить ${selectedIds.size} выбранных СИЗ?`)) return;

    try {
      await API.request('/api/v1/ppe_items/bulk-delete', {
        method: 'POST',
        body: JSON.stringify({ ids: Array.from(selectedIds) })
      });
      window.showToast('Выбранные СИЗ удалены', 'success');
      selectedIds.clear();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', (e) => {
      const checked = e.target.checked;
      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
      });
      updateBulkPanel();
    });
  }

  if (searchInput) searchInput.addEventListener('input', filterItems);
  if (filterFunction) filterFunction.addEventListener('change', filterItems);
  if (filterSizeGroup) filterSizeGroup.addEventListener('change', filterItems);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.function_id = payload.function_id ? Number(payload.function_id) : null;
    payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
    payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_items/', payload);
      window.showToast('Наименование создано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteItem = async (id, name) => {
    if (!confirm(`Удалить наименование "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_items/${id}`, { method: 'DELETE' });
      window.showToast('Наименование удалено', 'success');
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'item_updated') loadItems();
  });

  loadSelects();
  loadItems();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Панель стала компактной."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: compact bulk actions with edit/delete buttons in ppe_items list"
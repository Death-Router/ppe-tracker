#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем эндпоинты для массовых операций..."

python3 - << 'PYEOF'
with open('app/api/v1/endpoints/ppe_items.py', 'r') as f:
    content = f.read()

# Добавляем эндпоинты для массовых операций, если их нет
if '/bulk' not in content:
    new_endpoints = '''

# --- Массовые операции ---
from pydantic import BaseModel
from typing import List

class BulkUpdateRequest(BaseModel):
    ids: List[int]
    function_id: int | None = None
    size_group_id: int | None = None
    unit_id: int | None = None

@router.patch("/bulk")
async def bulk_update_items(
    data: BulkUpdateRequest, 
    db: AsyncSession = Depends(get_db)
):
    """Массовое обновление функций, размерных групп или единиц измерения для СИЗ."""
    if not data.ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одного СИЗ")

    result = await db.execute(select(PpeItem).where(PpeItem.id.in_(data.ids)))
    items = result.scalars().all()
    
    if not items:
        raise HTTPException(status_code=404, detail="СИЗ не найдены")

    for item in items:
        if data.function_id is not None:
            item.function_id = data.function_id if data.function_id != 0 else None
        if data.size_group_id is not None:
            item.size_group_id = data.size_group_id if data.size_group_id != 0 else None
        if data.unit_id is not None:
            item.unit_id = data.unit_id if data.unit_id != 0 else None
        item.version += 1

    await db.commit()
    return {"message": f"Обновлено {len(items)} записей"}


class BulkDeleteRequest(BaseModel):
    ids: List[int]

@router.post("/bulk-delete")
async def bulk_delete_items(
    data: BulkDeleteRequest, 
    db: AsyncSession = Depends(get_db)
):
    """Массовое удаление СИЗ с проверкой использования в нормах и выдачах."""
    if not data.ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одного СИЗ")

    # Проверяем, есть ли нормы или выдачи для этих СИЗ
    norm_exists = await db.execute(
        select(exists().where(PositionPpeNorm.ppe_item_id.in_(data.ids)))
    )
    if norm_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Некоторые СИЗ используются в нормах выдачи. Удаление запрещено."
        )

    issue_exists = await db.execute(
        select(exists().where(EmployeePpeIssue.ppe_item_id.in_(data.ids)))
    )
    if issue_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Некоторые СИЗ были выданы сотрудникам. Удаление запрещено."
        )

    await db.execute(delete(PpeItem).where(PpeItem.id.in_(data.ids)))
    await db.commit()
    return {"message": f"Удалено {len(data.ids)} записей"}
'''
    content += new_endpoints
    with open('app/api/v1/endpoints/ppe_items.py', 'w') as f:
        f.write(content)
    print("✅ Эндпоинты массовых операций добавлены.")
else:
    print("ℹ️ Эндпоинты уже есть.")
PYEOF

echo "📝 Обновляем шаблон списка СИЗ (чекбоксы и панель массовых действий)..."

cat > app/templates/ppe_items/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Наименования СИЗ</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<!-- Панель массовых действий (скрыта, пока ничего не выбрано) -->
<div id="bulk-actions" class="card shadow-sm mb-3 d-none">
    <div class="card-body py-2 d-flex align-items-center gap-2 flex-wrap">
        <span class="fw-bold me-2">Выбрано: <span id="selected-count">0</span></span>
        
        <select class="form-select form-select-sm" id="bulk-function" style="width: auto;">
            <option value="">-- Функция СИЗ --</option>
        </select>
        <button class="btn btn-sm btn-outline-primary" onclick="applyBulkFunction()">Применить</button>

        <select class="form-select form-select-sm" id="bulk-size-group" style="width: auto;">
            <option value="">-- Размерная группа --</option>
        </select>
        <button class="btn btn-sm btn-outline-primary" onclick="applyBulkSizeGroup()">Применить</button>

        <button class="btn btn-sm btn-outline-danger ms-auto" onclick="bulkDelete()">Удалить выбранные</button>
    </div>
</div>

<!-- Панель поиска и фильтрации -->
<div class="row g-2 mb-3">
    <div class="col-md-5">
        <div class="input-group">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
        </div>
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

<!-- Модальное окно создания -->
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
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/ppe_items_list.js') }}"></script>
{% endblock %}
EOF

echo "📝 Обновляем JS для списка СИЗ (чекбоксы, массовые действия)..."

cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createFunctionSelect = document.getElementById('create-function');
  const createSizeGroupSelect = document.getElementById('create-size-group');
  const createUnitSelect = document.getElementById('create-unit');
  const searchInput = document.getElementById('search-input');
  const bulkPanel = document.getElementById('bulk-actions');
  const bulkFunctionSelect = document.getElementById('bulk-function');
  const bulkSizeGroupSelect = document.getElementById('bulk-size-group');
  const selectAllCheckbox = document.getElementById('select-all');
  const selectedCountSpan = document.getElementById('selected-count');

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
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      bulkFunctionSelect.innerHTML = '<option value="">-- Функция СИЗ --</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');

      const groups = await API.get('/api/v1/ppe_size_groups');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      bulkSizeGroupSelect.innerHTML = '<option value="">-- Размерная группа --</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');

      const units = await API.get('/api/v1/units');
      createUnitSelect.innerHTML = '<option value="">Не указана</option>' +
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
    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.function?.name || '').toLowerCase().includes(searchTerm) ||
        (item.size_group?.name || '').toLowerCase().includes(searchTerm)
      );
    }

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

  window.applyBulkFunction = async () => {
    const funcId = bulkFunctionSelect.value;
    if (!funcId) {
      window.showToast('Выберите функцию', 'warning');
      return;
    }
    if (!selectedIds.size) return;

    try {
      await API.request('/api/v1/ppe_items/bulk', {
        method: 'PATCH',
        body: JSON.stringify({
          ids: Array.from(selectedIds),
          function_id: Number(funcId) || 0 // 0 = сбросить
        })
      });
      window.showToast('Функция назначена', 'success');
      selectedIds.clear();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  window.applyBulkSizeGroup = async () => {
    const groupId = bulkSizeGroupSelect.value;
    if (!groupId) {
      window.showToast('Выберите размерную группу', 'warning');
      return;
    }
    if (!selectedIds.size) return;

    try {
      await API.request('/api/v1/ppe_items/bulk', {
        method: 'PATCH',
        body: JSON.stringify({
          ids: Array.from(selectedIds),
          size_group_id: Number(groupId) || 0
        })
      });
      window.showToast('Размерная группа назначена', 'success');
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

  function updateBulkPanel() {
    const count = selectedIds.size;
    selectedCountSpan.textContent = count;
    if (count > 0) {
      bulkPanel.classList.remove('d-none');
    } else {
      bulkPanel.classList.add('d-none');
      selectAllCheckbox.checked = false;
    }
  }

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
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Массовые операции добавлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add bulk operations for ppe_items (assign function/size_group, bulk delete)"
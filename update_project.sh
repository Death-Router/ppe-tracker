#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем модалку создания СИЗ (функция и размерная группа)..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Заменяем поле "Категория" на два новых поля
old_block = '''          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
            </select>
          </div>'''

new_block = '''          <div class="mb-3">
            <label class="form-label">Функция СИЗ (Защита)</label>
            <select class="form-select" name="function_id" id="create-function">
                <option value="">Не указана</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">Размерная группа</label>
            <select class="form-select" name="size_group_id" id="create-size-group">
                <option value="">Не указана</option>
            </select>
          </div>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Модалка создания обновлена.")
else:
    print("⚠️ Не удалось найти блок категории в list.html.")
PYEOF

echo "📝 Обновляем карточку редактирования СИЗ..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/edit.html', 'r') as f:
    content = f.read()

# Заменяем поле "Категория" на два новых
old_block = '''                <div class="col-12">
                    <label class="form-label" for="category_id">Категория <span class="text-danger">*</span></label>
                    <select class="form-select" id="category_id" name="category_id" required>
                        <option value="">Загрузка...</option>
                    </select>
                    <div class="invalid-feedback">Выберите категорию.</div>
                </div>'''

new_block = '''                <div class="col-12">
                    <label class="form-label" for="function_id">Функция СИЗ (Защита)</label>
                    <select class="form-select" id="function_id" name="function_id">
                        <option value="">Не указана</option>
                    </select>
                </div>
                <div class="col-12">
                    <label class="form-label" for="size_group_id">Размерная группа</label>
                    <select class="form-select" id="size_group_id" name="size_group_id">
                        <option value="">Не указана</option>
                    </select>
                </div>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('app/templates/ppe_items/edit.html', 'w') as f:
        f.write(content)
    print("✅ Карточка редактирования обновлена.")
else:
    print("⚠️ Не удалось найти блок категории в edit.html.")
PYEOF

echo "📝 Обновляем JS для списка СИЗ..."

cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createFunctionSelect = document.getElementById('create-function');
  const createSizeGroupSelect = document.getElementById('create-size-group');
  const searchInput = document.getElementById('search-input');
  const categoryFilter = document.getElementById('category-filter');

  let allItems = [];

  async function loadItems() {
    try {
      allItems = await API.get('/api/v1/ppe_items');
      filterItems();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');

      const groups = await API.get('/api/v1/ppe_size_groups');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
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
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => {
      const fullName = escapeHtml(i.name);
      const shortName = escapeHtml(truncate(i.name, 60));
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">
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

echo "📝 Обновляем JS для карточки СИЗ..."

cat > app/static/js/ppe_item_edit.js << 'EOF'
(() => {
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const functionSelect = document.getElementById('function_id');
  const sizeGroupSelect = document.getElementById('size_group_id');
  const unitSelect = document.getElementById('unit_id');

  let isDirty = false;
  form.addEventListener('input', () => { isDirty = true; });

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      functionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');

      const groups = await API.get('/api/v1/ppe_size_groups');
      sizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');

      const units = await API.get('/api/v1/units');
      unitSelect.innerHTML = '<option value="">Не указана</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');
    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadItem(isWsUpdate = false) {
    try {
      const item = await API.get(`/api/v1/ppe_items/${itemId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = item.version ?? '';
        return;
      }

      form.elements['name'].value = item.name ?? '';
      functionSelect.value = item.function_id ?? '';
      sizeGroupSelect.value = item.size_group_id ?? '';
      unitSelect.value = item.unit_id ?? '';
      versionInput.value = item.version ?? '';

      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;

    const payload = FormHelper.serialize(form);
    payload.function_id = payload.function_id ? Number(payload.function_id) : null;
    payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
    payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

    try {
      const updated = await API.put(`/api/v1/ppe_items/${itemId}`, payload);
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
    if (data.event === 'item_updated' && data.item_id === itemId) {
      loadItem(true);
    }
  });

  loadSelects().then(() => loadItem());
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Формы СИЗ обновлены (функция и размерная группа)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace category with function and size_group in ppe_items forms"
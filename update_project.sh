#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем модалку создания СИЗ (добавляем размеры)..."

# Обновляем HTML-шаблон
python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Ищем блок с полем category_id в модалке создания
old_category_block = '''          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
            </select>
          </div>'''

# Добавляем после него блок с размерами
new_category_block = '''          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
            </select>
          </div>

          <div class="mb-3">
            <label class="form-label">Размеры (опционально)</label>
            <div class="input-group mb-2">
                <input type="text" class="form-control" id="new-size-input" placeholder="Например, 42">
                <select class="form-select" id="new-size-gender" style="max-width: 120px;">
                    <option value="">Унисекс</option>
                    <option value="М">Мужской</option>
                    <option value="Ж">Женский</option>
                </select>
                <button class="btn btn-outline-success" type="button" id="add-size-to-create-btn">+</button>
            </div>
            <ul class="list-group" id="create-sizes-list" style="max-height: 150px; overflow-y: auto;">
                <!-- Добавленные размеры будут здесь -->
            </ul>
          </div>'''

if old_category_block in content:
    content = content.replace(old_category_block, new_category_block)
    print("✅ Модалка создания обновлена (добавлен блок размеров).")
else:
    print("⚠️ Не удалось найти блок категории в модалке.")

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Обновляем JS логику создания СИЗ (с размерами)..."

cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createCategorySelect = document.getElementById('create-category');
  
  // Элементы модалки размеров (существующие)
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeItemName = document.getElementById('size-item-name');
  const sizeItemIdInput = document.getElementById('size-item-id');

  // Элементы для добавления размеров при создании СИЗ
  const newSizeInput = document.getElementById('new-size-input');
  const newSizeGender = document.getElementById('new-size-gender');
  const addSizeToCreateBtn = document.getElementById('add-size-to-create-btn');
  const createSizesList = document.getElementById('create-sizes-list');

  let pendingSizes = []; // Массив для хранения размеров, добавляемых при создании

  async function loadItems() {
    try {
      const items = await API.get('/api/v1/ppe_items');
      renderTable(items);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadCategoriesForSelect() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      createCategorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      createCategorySelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Наименований пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => `
      <tr data-item-id="${i.id}">
        <td><strong>${escapeHtml(i.name)}</strong></td>
        <td><span class="badge bg-secondary">${escapeHtml(i.category?.name ?? '—')}</span></td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-secondary" onclick="openSizesModal(${i.id}, '${escapeHtml(i.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteItem(${i.id}, '${escapeHtml(i.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // --- Добавление размера в список создания ---
  function renderPendingSizes() {
    if (!pendingSizes.length) {
      createSizesList.innerHTML = '<li class="list-group-item text-muted small">Размеры не добавлены</li>';
      return;
    }
    createSizesList.innerHTML = pendingSizes.map((s, idx) => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
        <li class="list-group-item d-flex justify-content-between align-items-center py-1">
          <span>${escapeHtml(s.size_value)}${genderLabel}</span>
          <button type="button" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="removePendingSize(${idx})">✕</button>
        </li>
      `;
    }).join('');
  }

  window.removePendingSize = (idx) => {
    pendingSizes.splice(idx, 1);
    renderPendingSizes();
  };

  addSizeToCreateBtn.addEventListener('click', () => {
    const val = newSizeInput.value.trim();
    if (!val) return;
    pendingSizes.push({ size_value: val, gender: newSizeGender.value || null });
    newSizeInput.value = '';
    renderPendingSizes();
  });

  // --- Создание СИЗ ---
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      // 1. Создаем СИЗ
      const createdItem = await API.post('/api/v1/ppe_items/', payload);
      window.showToast('Наименование создано', 'success');

      // 2. Создаем размеры для него (если есть)
      if (pendingSizes.length > 0) {
        for (const size of pendingSizes) {
          await API.post('/api/v1/ppe_sizes/', {
            ppe_item_id: createdItem.id,
            size_value: size.size_value,
            gender: size.gender
          });
        }
        window.showToast(`Добавлено размеров: ${pendingSizes.length}`, 'success');
      }

      // 3. Закрываем модалку и обновляем список
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      pendingSizes = [];
      renderPendingSizes();
      loadItems();
      
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // --- Удаление СИЗ ---
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

  // --- Управление размерами (модалка) ---
  window.openSizesModal = async (itemId, itemName) => {
    sizeItemIdInput.value = itemId;
    sizeItemName.textContent = itemName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = new bootstrap.Modal(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      renderSizesList(sizes);
    } catch (err) {
      sizesList.innerHTML = `<li class="list-group-item text-danger">Ошибка: ${err.message}</li>`;
    }
  };

  function renderSizesList(sizes) {
    if (!sizes.length) {
      sizesList.innerHTML = '<li class="list-group-item text-muted">Нет добавленных размеров</li>';
      return;
    }
    sizesList.innerHTML = sizes.map(s => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `}).join('');
  }

  // Добавление размера в модалке
  sizeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const itemId = Number(sizeItemIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { ppe_item_id: itemId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  // Удаление размера в модалке
  window.deleteSize = async (sizeId) => {
    if (!confirm('Удалить этот размер?')) return;
    try {
      await API.request(`/api/v1/ppe_sizes/${sizeId}`, { method: 'DELETE' });
      window.showToast('Размер удален', 'success');
      const itemId = Number(sizeItemIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'item_updated') {
      window.showToast(`Наименование #${data.item_id} изменено`, 'warning');
      loadItems();
    }
  });

  // Инициализация
  renderPendingSizes();
  loadCategoriesForSelect();
  loadItems();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь при создании СИЗ можно сразу добавлять размеры."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: allow adding sizes during PPE item creation"
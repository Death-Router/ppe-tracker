#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем шаблон категорий (добавляем поиск)..."

cat > app/templates/ppe_categories/list.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Категории СИЗ</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<!-- Панель поиска -->
<div class="row g-2 mb-3">
    <div class="col-md-5">
        <div class="input-group">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию или описанию...">
        </div>
    </div>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="categories-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Описание</th>
                <th class="text-end">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="3" class="text-center text-muted py-4">Загрузка…</td></tr>
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
          <h5 class="modal-title">Новая категория</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100">
          </div>
          <div class="mb-3">
            <label class="form-label">Описание</label>
            <textarea class="form-control" name="description" rows="2" maxlength="500"></textarea>
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

<!-- Модальное окно управления размерами категории -->
<div class="modal fade" id="sizesModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="size-form">
        <input type="hidden" name="category_id" id="size-category-id">
        <div class="modal-header">
          <h5 class="modal-title">Размеры для: <span id="size-category-name"></span></h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
            <div class="mb-3">
                <label class="form-label">Новый размер</label>
                <div class="row g-2">
                    <div class="col-4">
                        <select class="form-select" name="gender">
                            <option value="">Унисекс</option>
                            <option value="М">Мужской</option>
                            <option value="Ж">Женский</option>
                        </select>
                    </div>
                    <div class="col-5">
                        <input type="text" class="form-control" name="size_value" placeholder="Например, 42" required>
                    </div>
                    <div class="col-3">
                        <button class="btn btn-primary w-100" type="submit">Добавить</button>
                    </div>
                </div>
            </div>
            <ul class="list-group" id="sizes-list">
                <!-- Список размеров -->
            </ul>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/ppe_categories_list.js') }}"></script>
{% endblock %}
EOF

echo "📝 Обновляем JS категорий (компактный вывод, поиск)..."

cat > app/static/js/ppe_categories_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#categories-table tbody');
  const createForm = document.getElementById('create-form');
  const searchInput = document.getElementById('search-input');
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeCategoryName = document.getElementById('size-category-name');
  const sizeCategoryIdInput = document.getElementById('size-category-id');

  let allCategories = [];

  async function loadCategories() {
    try {
      allCategories = await API.get('/api/v1/ppe_categories');
      filterCategories();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterCategories() {
    const searchTerm = searchInput.value.toLowerCase().trim();
    let filtered = allCategories;

    if (searchTerm) {
      filtered = filtered.filter(c => 
        c.name.toLowerCase().includes(searchTerm) || 
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }

    renderTable(filtered);
  }

  function renderTable(categories) {
    if (!categories.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Ничего не найдено</td></tr>`;
      return;
    }
    tbody.innerHTML = categories.map(c => {
      const fullName = escapeHtml(c.name);
      const shortName = escapeHtml(truncate(c.name, 50));
      const shortDesc = escapeHtml(truncate(c.description ?? '', 60));
      return `
      <tr data-category-id="${c.id}" style="height: 40px;">
        <td class="py-1" title="${fullName}"><strong>${shortName}</strong></td>
        <td class="py-1" title="${escapeHtml(c.description ?? '')}">${shortDesc || '—'}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-secondary py-0 px-1" onclick="openSizesModal(${c.id}, '${fullName}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-categories/${c.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteCategory(${c.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  searchInput.addEventListener('input', filterCategories);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_categories/', payload);
      window.showToast('Категория создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteCategory = async (id, name) => {
    if (!confirm(`Удалить категорию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_categories/${id}`, { method: 'DELETE' });
      window.showToast('Категория удалена', 'success');
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // --- Управление размерами ---
  window.openSizesModal = async (categoryId, categoryName) => {
    sizeCategoryIdInput.value = categoryId;
    sizeCategoryName.textContent = categoryName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = new bootstrap.Modal(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
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
      <li class="list-group-item d-flex justify-content-between align-items-center py-1">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `}).join('');
  }

  sizeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const categoryId = Number(sizeCategoryIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { category_id: categoryId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  window.deleteSize = async (sizeId) => {
    if (!confirm('Удалить этот размер?')) return;
    try {
      await API.request(`/api/v1/ppe_sizes/${sizeId}`, { method: 'DELETE' });
      window.showToast('Размер удален', 'success');
      const categoryId = Number(sizeCategoryIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'category_updated') loadCategories();
  });

  loadCategories();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Категории стали компактными, добавлен поиск."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: compact categories table with search and truncated text"
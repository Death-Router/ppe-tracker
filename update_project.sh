#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем шаблон списка СИЗ (добавляем поиск и фильтр)..."

cat > app/templates/ppe_items/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Наименования СИЗ</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<!-- Панель поиска и фильтрации -->
<div class="row g-2 mb-3">
    <div class="col-md-5">
        <div class="input-group">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
        </div>
    </div>
    <div class="col-md-4">
        <select class="form-select" id="category-filter">
            <option value="">Все категории</option>
        </select>
    </div>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="items-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Наименование</th>
                <th>Категория</th>
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
          <h5 class="modal-title">Новое наименование СИЗ</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Наименование <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="255">
          </div>
          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
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

echo "📝 Обновляем JS (поиск, фильтр, обрезка длинных названий)..."

cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createCategorySelect = document.getElementById('create-category');
  const searchInput = document.getElementById('search-input');
  const categoryFilter = document.getElementById('category-filter');

  let allItems = [];

  async function loadItems() {
    try {
      allItems = await API.get('/api/v1/ppe_items');
      populateCategoryFilter(allItems);
      filterItems();
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
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

  function populateCategoryFilter(items) {
    const categories = [...new Set(items.map(i => i.category?.name).filter(Boolean))];
    categoryFilter.innerHTML = '<option value="">Все категории</option>' +
      categories.map(name => `<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`).join('');
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function truncate(str, maxLength) {
    if (!str) return '';
    if (str.length <= maxLength) return str;
    return str.substring(0, maxLength) + '...';
  }

  function filterItems() {
    const searchTerm = searchInput.value.toLowerCase().trim();
    const selectedCategory = categoryFilter.value;

    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.category?.name || '').toLowerCase().includes(searchTerm)
      );
    }

    if (selectedCategory) {
      filtered = filtered.filter(item => item.category?.name === selectedCategory);
    }

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
        <td class="py-1"><span class="badge bg-secondary">${escapeHtml(i.category?.name ?? '—')}</span></td>
        <td class="py-1 text-end">
          <a class="btn btn-sm btn-outline-primary py-0 px-1" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteItem(${i.id}, '${fullName}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  searchInput.addEventListener('input', filterItems);
  categoryFilter.addEventListener('change', filterItems);

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);
    
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

  loadCategoriesForSelect();
  loadItems();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Таблица стала компактнее, добавлены поиск и фильтр."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: compact ppe_items table with search, filter, and truncated names"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Возвращаем кнопки массовых операций в заголовок (рядом с 'Выбрано')..."

cat > app/templates/ppe_items/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<!-- Заголовок, счетчик выбранных и кнопки массовых операций -->
<div class="d-flex justify-content-between align-items-center mb-3">
    <div class="d-flex align-items-center gap-3 flex-wrap">
        <h1 class="h3 mb-0">Наименования СИЗ</h1>
        
        <!-- Блок массовых операций (появляется при выборе) -->
        <div id="bulk-actions" class="d-flex align-items-center gap-2 d-none">
            <span class="badge bg-secondary">Выбрано: <span id="selected-count">0</span></span>
            <button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-1" onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>
            <button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>
        </div>
    </div>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<!-- Панель фильтров -->
<div class="d-flex align-items-center gap-2 mb-3">
    <div class="input-group" style="width: 300px;">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    <select class="form-select" id="filter-function" style="width: auto;">
        <option value="">Все функции</option>
    </select>
    <select class="form-select" id="filter-size-group" style="width: auto;">
        <option value="">Все размерные группы</option>
    </select>
</div>

<!-- Таблица -->
<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="items-table">
            <thead class="bg-brand-orange">
            <tr>
                <th style="width: 40px;"><input type="checkbox" id="select-all"></th>
                <th>Наименование</th>
                <th style="width: 200px;">Функция / Группа</th>
                <th class="text-end" style="width: 120px;">Действия</th>
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

echo "📝 Обновляем JS для показа/скрытия блока массовых операций..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Заменяем ссылки на элементы (selectedCountSpan и т.д.)
content = content.replace(
    "const selectedCountSpan = document.getElementById('selected-count');",
    "const bulkActions = document.getElementById('bulk-actions');\n  const selectedCountSpan = document.getElementById('selected-count');"
)

# В updateBulkPanel показываем/скрываем bulkActions
old_update = '''  function updateBulkPanel() {
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
  }'''

new_update = '''  function updateBulkPanel() {
    const count = selectedIds.size;
    if (count > 0) {
      bulkActions.classList.remove('d-none');
      selectedCountSpan.textContent = count;
    } else {
      bulkActions.classList.add('d-none');
      selectAllCheckbox.checked = false;
    }
  }'''

if old_update in content:
    content = content.replace(old_update, new_update)
    print("✅ JS обновлен (показ/скрытие блока массовых операций).")
else:
    print("⚠️ Не удалось найти updateBulkPanel в JS.")

# Убираем лишние disabled у кнопок (они не нужны, блок и так скрыт)
content = content.replace(' disabled onclick="openBulkEditModal()"', ' onclick="openBulkEditModal()"')
content = content.replace(' disabled onclick="bulkDelete()"', ' onclick="bulkDelete()"')

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки появляются после заголовка 'Выбрано'."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: move bulk actions to header after 'selected' badge"
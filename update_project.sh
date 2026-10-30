#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно перезаписываем шаблоны с кнопкой '+' (фиолетовая, слева)..."

# 1. Размерные группы
cat > app/templates/ppe_size_groups/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Размерные группы</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="groups-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="2" class="text-center text-muted py-4">Загрузка…</td></tr>
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
          <h5 class="modal-title">Новая размерная группа</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100" placeholder="Например, Обувь">
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
<script src="{{ url_for('static', path='js/ppe_size_groups_list.js') }}"></script>
{% endblock %}
EOF

# 2. Единицы измерения
cat > app/templates/units/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Единицы измерения</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="units-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Сокращение</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="3" class="text-center text-muted py-4">Загрузка…</td></tr>
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
          <h5 class="modal-title">Новая единица измерения</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="50" placeholder="Например, Пара">
          </div>
          <div class="mb-3">
            <label class="form-label">Сокращение <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="short_name" required maxlength="10" placeholder="Например, пар">
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
<script src="{{ url_for('static', path='js/units_list.js') }}"></script>
{% endblock %}
EOF

# 3. Подразделения
cat > app/templates/departments/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Подразделения</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="departments-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Вышестоящее</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="3" class="text-center text-muted py-4">Загрузка…</td></tr>
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
          <h5 class="modal-title">Новое подразделение</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100">
          </div>
          <div class="mb-3">
            <label class="form-label">Вышестоящее подразделение</label>
            <select class="form-select" name="parent_id" id="create-parent">
                <option value="">Нет (корневое)</option>
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
<script src="{{ url_for('static', path='js/departments_list.js') }}"></script>
{% endblock %}
EOF

# 4. Должности
cat > app/templates/positions/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Должности</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="positions-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Подразделение</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="3" class="text-center text-muted py-4">Загрузка…</td></tr>
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
          <h5 class="modal-title">Новая должность</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100">
          </div>
          <div class="mb-3">
            <label class="form-label">Подразделение <span class="text-danger">*</span></label>
            <select class="form-select" name="department_id" id="create-dept" required>
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
<script src="{{ url_for('static', path='js/positions_list.js') }}"></script>
{% endblock %}
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шаблоны перезаписаны (кнопка '+' фиолетовая, слева)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force rewrite list templates with purple add button (left)"
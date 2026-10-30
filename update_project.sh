#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно перезаписываем шаблон сотрудников (фиолетовая '+' слева)..."

cat > app/templates/employees/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Сотрудники</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="employees-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>ФИО</th>
                <th>Табельный номер</th>
                <th>Подразделение</th>
                <th>Должность</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="5" class="text-center text-muted py-4">Загрузка…</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Модалка создания -->
<div class="modal fade" id="createModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <form id="create-form" data-validate="true">
        <div class="modal-header">
          <h5 class="modal-title">Новый сотрудник</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
            <div class="row g-3">
                <div class="col-md-4">
                    <label class="form-label">Фамилия <span class="text-danger">*</span></label>
                    <input class="form-control" name="last_name" required maxlength="100">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Имя <span class="text-danger">*</span></label>
                    <input class="form-control" name="first_name" required maxlength="100">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Отчество</label>
                    <input class="form-control" name="middle_name" maxlength="100">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Табельный номер <span class="text-danger">*</span></label>
                    <input class="form-control" name="personnel_number" required maxlength="20">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Подразделение <span class="text-danger">*</span></label>
                    <select class="form-select" name="department_id" id="create-dept" required>
                        <option value="">Загрузка...</option>
                    </select>
                </div>
                <div class="col-md-4">
                    <label class="form-label">Должность <span class="text-danger">*</span></label>
                    <select class="form-select" name="position_id" id="create-pos" required>
                        <option value="">Сначала выберите подразделение</option>
                    </select>
                </div>
                <div class="col-md-3">
                    <label class="form-label">Дата приема <span class="text-danger">*</span></label>
                    <input type="date" class="form-control" name="hire_date" required>
                </div>
                <div class="col-md-3">
                    <label class="form-label">Пол <span class="text-danger">*</span></label>
                    <select class="form-select" name="gender" required>
                        <option value="">Не указан</option>
                        <option value="М">Мужской</option>
                        <option value="Ж">Женский</option>
                    </select>
                </div>
                <div class="col-md-3">
                    <label class="form-label">Рост <span class="text-danger">*</span></label>
                    <input class="form-control" name="height" placeholder="Например, 182" maxlength="10" required>
                </div>
            </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-brand-orange" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-brand-purple">Создать</button>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/employees_list.js') }}"></script>
{% endblock %}
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Шаблон сотрудников перезаписан."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: force rewrite employees list template with purple add button (left)"
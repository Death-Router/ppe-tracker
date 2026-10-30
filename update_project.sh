#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Переделываем страницу настроек (добавляем вкладку 'Пользователи')..."

cat > app/templates/settings.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-10">
        <h1 class="h3 mb-4">Настройки</h1>

        <!-- Вкладки -->
        <ul class="nav nav-tabs mb-3" id="settingsTabs" role="tablist">
            <li class="nav-item" role="presentation">
                <button class="nav-link active" id="import-export-tab" data-bs-toggle="tab" data-bs-target="#import-export" type="button" role="tab">Импорт / Экспорт</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="users-tab" data-bs-toggle="tab" data-bs-target="#users" type="button" role="tab">Пользователи</button>
            </li>
        </ul>

        <div class="tab-content" id="settingsTabsContent">
            <!-- Вкладка Импорт/Экспорт -->
            <div class="tab-pane fade show active" id="import-export" role="tabpanel">
                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-white">
                        <h5 class="mb-0 text-secondary"><i class="bi bi-download"></i> Экспорт данных</h5>
                    </div>
                    <div class="card-body">
                        <p class="text-muted small mb-3">Выгрузите текущие данные в формате Excel.</p>
                        <div class="d-flex gap-2 flex-wrap">
                            <a href="/api/v1/export/employees" class="btn btn-brand-purple" download>
                                <i class="bi bi-file-earmark-excel"></i> Скачать сотрудников
                            </a>
                            <a href="/api/v1/export/ppe-items" class="btn btn-brand-purple" download>
                                <i class="bi bi-file-earmark-excel"></i> Скачать СИЗ
                            </a>
                            <a href="/api/v1/export/norms" class="btn btn-brand-purple" download>
                                <i class="bi bi-file-earmark-excel"></i> Скачать нормы
                            </a>
                        </div>
                    </div>
                </div>

                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-white">
                        <h5 class="mb-0 text-secondary"><i class="bi bi-upload"></i> Импорт данных</h5>
                    </div>
                    <div class="card-body">
                        <p class="text-muted small mb-3">Загрузите Excel-файл с сотрудниками.</p>
                        <form id="import-form" enctype="multipart/form-data" data-validate="true">
                            <div class="input-group mb-3">
                                <input type="file" class="form-control" name="file" accept=".xlsx, .xls" required>
                                <button type="submit" class="btn btn-brand-purple" id="import-btn">Загрузить</button>
                            </div>
                            <div id="import-result" class="mt-3"></div>
                        </form>
                    </div>
                </div>

                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-white">
                        <h5 class="mb-0 text-secondary"><i class="bi bi-upload"></i> Импорт СИЗ</h5>
                    </div>
                    <div class="card-body">
                        <p class="text-muted small mb-3">Загрузите Excel-файл с колонками: "Наименование", "Категория".</p>
                        <form id="import-items-form" enctype="multipart/form-data">
                            <div class="input-group mb-3">
                                <input type="file" class="form-control" name="file" accept=".xlsx, .xls" required>
                                <button type="submit" class="btn btn-brand-purple">Загрузить</button>
                            </div>
                            <div id="import-items-result" class="mt-3"></div>
                        </form>
                    </div>
                </div>

                <div class="card shadow-sm mb-4">
                    <div class="card-header bg-white">
                        <h5 class="mb-0 text-secondary"><i class="bi bi-upload"></i> Импорт Норм</h5>
                    </div>
                    <div class="card-body">
                        <p class="text-muted small mb-3">Загрузите Excel-файл с колонками: "Подразделение", "Должность", "СИЗ", "Срок", "Количество".</p>
                        <form id="import-norms-form" enctype="multipart/form-data">
                            <div class="input-group mb-3">
                                <input type="file" class="form-control" name="file" accept=".xlsx, .xls" required>
                                <button type="submit" class="btn btn-brand-purple">Загрузить</button>
                            </div>
                            <div id="import-norms-result" class="mt-3"></div>
                        </form>
                    </div>
                </div>
            </div>

            <!-- Вкладка Пользователи -->
            <div class="tab-pane fade" id="users" role="tabpanel">
                <div class="d-flex align-items-center gap-2 mb-3">
                    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createUserModal" title="Добавить">
                        <i class="bi bi-plus-lg"></i>
                    </button>
                    <h5 class="mb-0">Пользователи</h5>
                </div>

                <div class="card shadow-sm">
                    <div class="table-responsive">
                        <table class="table table-sm table-hover align-middle mb-0" id="users-table">
                            <thead class="bg-brand-purple">
                            <tr>
                                <th>Логин</th>
                                <th>Роль</th>
                                <th>Подразделение</th>
                                <th>Активен</th>
                                <th class="text-end" style="width: 120px;">Действия</th>
                            </tr>
                            </thead>
                            <tbody>
                            <tr><td colspan="5" class="text-center text-muted py-4">Загрузка…</td></tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Модалка создания/редактирования пользователя -->
<div class="modal fade" id="createUserModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="user-form" data-validate="true">
        <input type="hidden" name="user_id" id="user-id" value="">
        <div class="modal-header">
          <h5 class="modal-title" id="user-modal-title">Новый пользователь</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Логин <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="username" required maxlength="50">
          </div>
          <div class="mb-3">
            <label class="form-label">Пароль <span class="text-danger">*</span></label>
            <input type="password" class="form-control" name="password" id="password" required minlength="6">
            <div class="form-text" id="password-hint" style="display: none;">Оставьте пустым, чтобы не менять.</div>
          </div>
          <div class="mb-3">
            <label class="form-label">Роль <span class="text-danger">*</span></label>
            <select class="form-select" name="role" id="role-select" required>
                <option value="safety_officer">Специалист ОТ</option>
                <option value="admin">Администратор</option>
            </select>
          </div>
          <div class="mb-3" id="department-group">
            <label class="form-label">Подразделение</label>
            <select class="form-select" name="department_id" id="department-select">
                <option value="">Не указано</option>
            </select>
          </div>
          <div class="mb-3" id="subdep-group">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="include_subdepartments" id="include-subdep">
              <label class="form-check-label" for="include-subdep">
                Включать дочерние подразделения
              </label>
            </div>
          </div>
          <div class="mb-3">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="is_active" id="is-active" checked>
              <label class="form-check-label" for="is-active">Активен</label>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-brand-orange" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-brand-purple">Сохранить</button>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/settings.js') }}"></script>
<script src="{{ url_for('static', path='js/users_list.js') }}"></script>
{% endblock %}
EOF

echo "📝 Обновляем JS для пользователей (чтобы работал на странице настроек)..."

cat > app/static/js/users_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#users-table tbody');
  const form = document.getElementById('user-form');
  const modalTitle = document.getElementById('user-modal-title');
  const userIdInput = document.getElementById('user-id');
  const passwordInput = document.getElementById('password');
  const passwordHint = document.getElementById('password-hint');
  const roleSelect = document.getElementById('role-select');
  const departmentSelect = document.getElementById('department-select');
  const departmentGroup = document.getElementById('department-group');
  const subdepGroup = document.getElementById('subdep-group');
  const includeSubdep = document.getElementById('include-subdep');

  // Если на странице нет таблицы пользователей, просто выходим
  if (!tbody) return;

  let allUsers = [];
  let allDepartments = [];
  let editingId = null;

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadData() {
    try {
      allUsers = await API.get('/api/v1/users');
      allDepartments = await API.get('/api/v1/departments');
      renderTable(allUsers);
      
      const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
      if (departmentSelect) {
        departmentSelect.innerHTML = '<option value="">Не указано</option>' +
          sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(users) {
    if (!users.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-4">Пользователей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = users.map(u => {
      const deptName = allDepartments.find(d => d.id === u.department_id)?.name || '—';
      const roleName = u.role === 'admin' ? 'Администратор' : 'Специалист ОТ';
      return `
      <tr data-user-id="${u.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(u.username)}</strong></td>
        <td class="py-1"><span class="badge bg-purple">${roleName}</span></td>
        <td class="py-1">${escapeHtml(deptName)}</td>
        <td class="py-1">${u.is_active ? '<span class="badge bg-success">Да</span>' : '<span class="badge bg-danger">Нет</span>'}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editUser(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUser(${u.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новый пользователь';
    userIdInput.value = '';
    form.reset();
    passwordInput.required = true;
    passwordHint.style.display = 'none';
    new bootstrap.Modal(document.getElementById('createUserModal')).show();
  };

  window.editUser = async (id) => {
    try {
      const user = allUsers.find(u => u.id === id);
      if (!user) throw new Error('Пользователь не найден');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование пользователя';
      userIdInput.value = id;
      
      form.elements['username'].value = user.username;
      passwordInput.value = '';
      passwordInput.required = false;
      passwordHint.style.display = 'block';
      
      roleSelect.value = user.role;
      departmentSelect.value = user.department_id || '';
      includeSubdep.checked = user.include_subdepartments || false;
      form.elements['is_active'].checked = user.is_active;
      
      new bootstrap.Modal(document.getElementById('createUserModal')).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(form);
    
    if (payload.department_id) {
      payload.department_id = Number(payload.department_id);
    } else {
      payload.department_id = null;
    }
    
    payload.include_subdepartments = includeSubdep.checked;
    payload.is_active = form.elements['is_active'].checked;
    
    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        if (!payload.password) delete payload.password;
        await API.put(`/api/v1/users/${editingId}`, payload);
        window.showToast('Пользователь обновлен', 'success');
      } else {
        await API.post('/api/v1/users/', payload);
        window.showToast('Пользователь создан', 'success');
      }
      bootstrap.Modal.getInstance(document.getElementById('createUserModal')).hide();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteUser = async (id) => {
    if (!confirm('Удалить этого пользователя?')) return;
    try {
      await API.request(`/api/v1/users/${id}`, { method: 'DELETE' });
      window.showToast('Пользователь удален', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.querySelector('button[data-bs-target="#createUserModal"]')?.addEventListener('click', openCreateModal);

  loadData();
})();
EOF

echo "📝 Создаем JS для страницы настроек (импорт/экспорт)..."

cat > app/static/js/settings.js << 'EOF'
(() => {
  // Импорт сотрудников
  document.getElementById('import-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-result');
    const btn = document.getElementById('import-btn');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/employees', { method: 'POST', body: formData });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}, Обновлено: ${data.updated}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Загрузить';
    }
  });

  // Импорт СИЗ
  document.getElementById('import-items-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-items-result');
    const btn = form.querySelector('button[type="submit"]');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/ppe-items', { method: 'POST', body: formData });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт СИЗ выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Загрузить';
    }
  });

  // Импорт Норм
  document.getElementById('import-norms-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-norms-result');
    const btn = form.querySelector('button[type="submit"]');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/norms', { method: 'POST', body: formData });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт норм выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Загрузить';
    }
  });
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Вкладка 'Пользователи' добавлена в настройки."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add users management tab to settings page"
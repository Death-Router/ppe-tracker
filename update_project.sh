#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем страницы для Функций СИЗ и Размерных групп..."

# 1. Создаем шаблон для функций
mkdir -p app/templates/ppe_functions
cat > app/templates/ppe_functions/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Функции СИЗ (Защита)</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="functions-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th class="text-end">Действия</th>
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
          <h5 class="modal-title">Новая функция</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100">
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
<script src="{{ url_for('static', path='js/ppe_functions_list.js') }}"></script>
{% endblock %}
EOF

# 2. JS для функций
cat > app/static/js/ppe_functions_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadFunctions() {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      renderTable(funcs);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(funcs) {
    if (!funcs.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Функций пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = funcs.map(f => `
      <tr data-id="${f.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(f.name)}</strong></td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_functions/', payload);
      window.showToast('Функция создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteFunction = async (id, name) => {
    if (!confirm(`Удалить функцию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_functions/${id}`, { method: 'DELETE' });
      window.showToast('Функция удалена', 'success');
      loadFunctions();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  loadFunctions();
})();
EOF

echo "📝 Создаем страницы для Размерных групп..."

# 3. Шаблон для размерных групп
mkdir -p app/templates/ppe_size_groups
cat > app/templates/ppe_size_groups/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Размерные группы</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="groups-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th class="text-end">Действия</th>
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

# 4. JS для размерных групп
cat > app/static/js/ppe_size_groups_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadGroups() {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      renderTable(groups);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(groups) {
    if (!groups.length) {
      tbody.innerHTML = `<tr><td colspan="2" class="text-center text-muted py-4">Групп пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = groups.map(g => `
      <tr data-id="${g.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(g.name)}</strong></td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_size_groups/', payload);
      window.showToast('Размерная группа создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteGroup = async (id, name) => {
    if (!confirm(`Удалить размерную группу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_size_groups/${id}`, { method: 'DELETE' });
      window.showToast('Размерная группа удалена', 'success');
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  loadGroups();
})();
EOF

echo "🔧 Добавляем маршруты в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Добавляем маршруты для страниц, если их нет
if '/ppe-functions' not in content:
    route = '''
@app.get("/ppe-functions", response_class=HTMLResponse)
async def ppe_functions_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_functions/list.html",
        context={"title": "Функции СИЗ"},
    )

@app.get("/ppe-size-groups", response_class=HTMLResponse)
async def ppe_size_groups_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_size_groups/list.html",
        context={"title": "Размерные группы"},
    )
'''
    content += route
    with open('app/main.py', 'w') as f:
        f.write(content)
    print("✅ Маршруты добавлены.")
else:
    print("ℹ️ Маршруты уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Страницы для функций и размерных групп созданы."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add pages for ppe_functions and ppe_size_groups"
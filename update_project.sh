#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем кнопки редактирования в списки функций и размерных групп..."

# --- Функции СИЗ ---
# 1. Обновляем шаблон (добавляем кнопку в таблицу)
python3 - << 'PYEOF'
with open('app/templates/ppe_functions/list.html', 'r') as f:
    content = f.read()

# В строке действий добавляем кнопку "Редактировать"
old_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

new_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editFunction(${f.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

if old_actions in content:
    content = content.replace(old_actions, new_actions)
    print("✅ Шаблон функций обновлен (добавлена кнопка редактирования).")
else:
    print("⚠️ Не удалось найти блок действий в шаблоне функций.")

with open('app/templates/ppe_functions/list.html', 'w') as f:
    f.write(content)
PYEOF

# 2. Обновляем JS для функций (добавляем editFunction)
cat > app/static/js/ppe_functions_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#functions-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;

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
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editFunction(${f.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteFunction(${f.id}, '${escapeHtml(f.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новая функция';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    new bootstrap.Modal(modalElement).show();
  };

  // Редактирование
  window.editFunction = async (id) => {
    try {
      const funcs = await API.get('/api/v1/ppe_functions');
      const func = funcs.find(f => f.id === id);
      if (!func) throw new Error('Функция не найдена');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование функции';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = func.name;
      
      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        payload.version = (await API.get(`/api/v1/ppe_functions/${editingId}`)).version;
        await API.put(`/api/v1/ppe_functions/${editingId}`, payload);
        window.showToast('Функция обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_functions/', payload);
        window.showToast('Функция создана', 'success');
      }
      bootstrap.Modal.getInstance(modalElement).hide();
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

  // Привязка кнопки "Добавить" к открытию модалки
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadFunctions();
})();
EOF

echo "✅ JS для функций обновлен (добавлена editFunction)."

# --- Размерные группы ---
# 1. Обновляем шаблон
python3 - << 'PYEOF'
with open('app/templates/ppe_size_groups/list.html', 'r') as f:
    content = f.read()

old_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

new_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

if old_actions in content:
    content = content.replace(old_actions, new_actions)
    print("✅ Шаблон групп обновлен (добавлена кнопка редактирования).")
else:
    print("⚠️ Не удалось найти блок действий в шаблоне групп.")

with open('app/templates/ppe_size_groups/list.html', 'w') as f:
    f.write(content)
PYEOF

# 2. Обновляем JS для групп
cat > app/static/js/ppe_size_groups_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  let editingId = null;

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
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новая размерная группа';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    new bootstrap.Modal(modalElement).show();
  };

  window.editGroup = async (id) => {
    try {
      const groups = await API.get('/api/v1/ppe_size_groups');
      const group = groups.find(g => g.id === id);
      if (!group) throw new Error('Группа не найдена');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование группы';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['name'].value = group.name;
      
      new bootstrap.Modal(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        payload.version = (await API.get(`/api/v1/ppe_size_groups/${editingId}`)).version;
        await API.put(`/api/v1/ppe_size_groups/${editingId}`, payload);
        window.showToast('Группа обновлена', 'success');
      } else {
        await API.post('/api/v1/ppe_size_groups/', payload);
        window.showToast('Группа создана', 'success');
      }
      bootstrap.Modal.getInstance(modalElement).hide();
      createForm.reset();
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteGroup = async (id, name) => {
    if (!confirm(`Удалить группу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_size_groups/${id}`, { method: 'DELETE' });
      window.showToast('Группа удалена', 'success');
      loadGroups();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadGroups();
})();
EOF

echo "✅ JS для групп обновлен (добавлена editGroup)."

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки редактирования добавлены в функции и размерные группы."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add edit buttons to ppe_functions and ppe_size_groups lists"
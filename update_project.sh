#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Восстанавливаем управление размерами в размерных группах..."

# 1. Добавляем кнопку "Размеры" в таблицу и модалку в шаблон
python3 - << 'PYEOF'
with open('app/templates/ppe_size_groups/list.html', 'r') as f:
    content = f.read()

# Добавляем кнопку "Размеры" в таблицу (рядом с карандашом)
old_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

new_actions = '''        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-secondary py-0 px-1" onclick="openSizesModal(${g.id}, '${escapeHtml(g.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>'''

if old_actions in content:
    content = content.replace(old_actions, new_actions)
    print("✅ Кнопка 'Размеры' добавлена в таблицу.")
else:
    print("⚠️ Не удалось найти блок действий в таблице.")

# Добавляем модалку для управления размерами в конец блока content
modal_html = '''
<!-- Модалка управления размерами -->
<div class="modal fade" id="sizesModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="size-form">
        <input type="hidden" name="size_group_id" id="size-group-id">
        <div class="modal-header">
          <h5 class="modal-title">Размеры для: <span id="size-group-name"></span></h5>
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
                        <button class="btn btn-brand-purple w-100" type="submit">Добавить</button>
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
'''

# Вставляем перед {% endblock %}
if 'id="sizesModal"' not in content:
    content = content.replace('{% endblock %}', modal_html + '\n{% endblock %}')
    print("✅ Модалка размеров добавлена.")

with open('app/templates/ppe_size_groups/list.html', 'w') as f:
    f.write(content)
PYEOF

# 2. Обновляем JS (добавляем логику для модалки размеров)
cat > app/static/js/ppe_size_groups_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#groups-table tbody');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement.querySelector('.modal-title');
  const submitBtn = modalElement.querySelector('button[type="submit"]');

  // Элементы модалки размеров
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeGroupName = document.getElementById('size-group-name');
  const sizeGroupIdInput = document.getElementById('size-group-id');

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
          <button class="btn btn-sm btn-outline-secondary py-0 px-1" onclick="openSizesModal(${g.id}, '${escapeHtml(g.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editGroup(${g.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteGroup(${g.id}, '${escapeHtml(g.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания/редактирования группы
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

  // --- Управление размерами ---
  window.openSizesModal = async (groupId, groupName) => {
    sizeGroupIdInput.value = groupId;
    sizeGroupName.textContent = groupName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = new bootstrap.Modal(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
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
    const groupId = Number(sizeGroupIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { size_group_id: groupId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
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
      const groupId = Number(sizeGroupIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${groupId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadGroups();
})();
EOF

echo "✅ JS для размерных групп обновлен (добавлена логика размеров)."

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Управление размерами восстановлено в размерных группах."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: restore sizes management in ppe_size_groups"
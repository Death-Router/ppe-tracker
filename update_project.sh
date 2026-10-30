#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Перезаписываем ppe_item_edit.js (без category)..."

cat > app/static/js/ppe_item_edit.js << 'EOF'
(() => {
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const functionSelect = document.getElementById('function_id');
  const sizeGroupSelect = document.getElementById('size_group_id');
  const unitSelect = document.getElementById('unit_id');

  let isDirty = false;
  form.addEventListener('input', () => { isDirty = true; });

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      functionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');

      const groups = await API.get('/api/v1/ppe_size_groups');
      sizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');

      const units = await API.get('/api/v1/units');
      unitSelect.innerHTML = '<option value="">Не указана</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');
    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadItem(isWsUpdate = false) {
    try {
      const item = await API.get(`/api/v1/ppe_items/${itemId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = item.version ?? '';
        return;
      }

      form.elements['name'].value = item.name ?? '';
      functionSelect.value = item.function_id ?? '';
      sizeGroupSelect.value = item.size_group_id ?? '';
      unitSelect.value = item.unit_id ?? '';
      versionInput.value = item.version ?? '';

      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;

    const payload = FormHelper.serialize(form);
    payload.function_id = payload.function_id ? Number(payload.function_id) : null;
    payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
    payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

    try {
      const updated = await API.put(`/api/v1/ppe_items/${itemId}`, payload);
      if (updated?.version != null) versionInput.value = updated.version;
      isDirty = false;
      window.showToast('Изменения сохранены', 'success');
    } catch (err) {
      if (err.isConflict) {
        conflictAlert.classList.remove('d-none');
        conflictAlert.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } else {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      }
    } finally {
      btnSubmit.disabled = false;
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'item_updated' && data.item_id === itemId) {
      loadItem(true);
    }
  });

  loadSelects().then(() => loadItem());
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Ошибка должна исчезнуть."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: fully rewrite ppe_item_edit.js without category references"
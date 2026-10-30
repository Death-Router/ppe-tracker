#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Проверяем id в edit.html и приводим к единому виду..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/edit.html', 'r') as f:
    content = f.read()

# Проверяем, какие id есть в HTML
import re
ids = re.findall(r'id="([^"]+)"', content)
print("🔍 Найденные id в edit.html:", ids)

# Если нет function_id, size_group_id, unit_id — добавляем/заменяем
# Ищем поля по name и заменяем id
replacements = [
    ('name="function_id"', 'id="function_id"'),
    ('name="size_group_id"', 'id="size_group_id"'),
    ('name="unit_id"', 'id="unit_id"'),
]

for name_attr, id_attr in replacements:
    if id_attr not in content and name_attr in content:
        # Добавляем id к элементу с name
        content = re.sub(r'(<select[^>]*' + re.escape(name_attr) + r'[^>]*)(>)', r'\1 ' + id_attr + r'\2', content)
        print(f"✅ Добавлен {id_attr}")

with open('app/templates/ppe_items/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "🔧 Упрощаем JS (ищем элементы по name, если id не найден)..."

cat > app/static/js/ppe_item_edit.js << 'EOF'
(() => {
  console.log('🚀 ppe_item_edit.js загружен');
  
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');

  // Ищем элементы по name, если id не найден
  const functionSelect = document.getElementById('function_id') || form.elements['function_id'];
  const sizeGroupSelect = document.getElementById('size_group_id') || form.elements['size_group_id'];
  const unitSelect = document.getElementById('unit_id') || form.elements['unit_id'];

  console.log('🔍 functionSelect:', functionSelect);
  console.log('🔍 sizeGroupSelect:', sizeGroupSelect);
  console.log('🔍 unitSelect:', unitSelect);

  if (!form || !functionSelect || !sizeGroupSelect || !unitSelect) {
    console.error('❌ Один или несколько элементов не найдены!');
    return;
  }

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

      if (form.elements['name']) form.elements['name'].value = item.name ?? '';
      if (functionSelect) functionSelect.value = item.function_id ?? '';
      if (sizeGroupSelect) sizeGroupSelect.value = item.size_group_id ?? '';
      if (unitSelect) unitSelect.value = item.unit_id ?? '';
      if (versionInput) versionInput.value = item.version ?? '';

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

echo "✅ ГОТОВО! Теперь JS ищет элементы по name (если id не найден)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: use name fallback for selects in ppe_item_edit.js"
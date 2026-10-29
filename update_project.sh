#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Добавляем поле 'Единица измерения' в форму редактирования СИЗ..."

# 1. Обновляем шаблон edit.html
python3 - << 'PYEOF'
with open('app/templates/ppe_items/edit.html', 'r') as f:
    content = f.read()

# Ищем блок с категорией и добавляем после него блок с единицей
old_block = '''                <div class="col-12">
                    <label class="form-label" for="category_id">Категория <span class="text-danger">*</span></label>
                    <select class="form-select" id="category_id" name="category_id" required>
                        <option value="">Загрузка...</option>
                    </select>
                    <div class="invalid-feedback">Выберите категорию.</div>
                </div>'''

new_block = '''                <div class="col-12">
                    <label class="form-label" for="category_id">Категория <span class="text-danger">*</span></label>
                    <select class="form-select" id="category_id" name="category_id" required>
                        <option value="">Загрузка...</option>
                    </select>
                    <div class="invalid-feedback">Выберите категорию.</div>
                </div>
                <div class="col-12">
                    <label class="form-label" for="unit_id">Единица измерения</label>
                    <select class="form-select" id="unit_id" name="unit_id">
                        <option value="">Не указана</option>
                    </select>
                </div>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('app/templates/ppe_items/edit.html', 'w') as f:
        f.write(content)
    print("✅ Поле единицы добавлено в edit.html.")
else:
    print("⚠️ Не удалось найти блок категории в edit.html.")
PYEOF

echo "📝 Обновляем JS для карточки СИЗ (загрузка и сохранение единицы)..."

# 2. Обновляем JS
cat > app/static/js/ppe_item_edit.js << 'EOF'
(() => {
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const categorySelect = document.getElementById('category_id');
  const unitSelect = document.getElementById('unit_id');

  let isDirty = false;
  form.addEventListener('input', () => { isDirty = true; });

  // Загрузка категорий и единиц
  async function loadSelects() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      categorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');

      const units = await API.get('/api/v1/units');
      unitSelect.innerHTML = '<option value="">Не указана</option>' +
        units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');
    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  // Загрузка данных СИЗ
  async function loadItem(isWsUpdate = false) {
    try {
      const item = await API.get(`/api/v1/ppe_items/${itemId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = item.version ?? '';
        return;
      }

      form.elements['name'].value = item.name ?? '';
      categorySelect.value = item.category_id ?? '';
      unitSelect.value = item.unit_id ?? '';
      versionInput.value = item.version ?? '';

      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // Сохранение
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;

    const payload = FormHelper.serialize(form);
    payload.category_id = Number(payload.category_id);
    if (payload.unit_id) {
      payload.unit_id = Number(payload.unit_id);
    } else {
      payload.unit_id = null;
    }

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

  // Инициализация: сначала справочники, потом данные
  loadSelects().then(() => loadItem());
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Единица измерения добавлена в карточку СИЗ."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add unit field to ppe_item edit form"
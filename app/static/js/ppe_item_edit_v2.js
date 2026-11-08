(() => {
  console.log('🚀 ppe_item_edit.js загружен (версия с отладкой)');
  
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');

  const functionSelect = document.querySelector('select[name="function_id"]');
  const sizeGroupSelect = document.querySelector('select[name="size_group_id"]');
  const unitSelect = document.querySelector('select[name="unit_id"]');

  console.log('form:', form);
  console.log('functionSelect:', functionSelect);
  console.log('sizeGroupSelect:', sizeGroupSelect);
  console.log('unitSelect:', unitSelect);

  if (!functionSelect) console.error('❌ functionSelect не найден!');
  if (!sizeGroupSelect) console.error('❌ sizeGroupSelect не найден!');
  if (!unitSelect) console.error('❌ unitSelect не найден!');

  if (!form) {
    console.error('❌ Форма item-form не найдена!');
    return;
  }

  let isDirty = false;
  form.addEventListener('input', () => { isDirty = true; });

  async function loadSelects() {
    try {
      const functions = await API.get('/api/v1/ppe_functions');
      if (functionSelect) {
        functionSelect.innerHTML = '<option value="">Не указана</option>' +
          functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      }

      const groups = await API.get('/api/v1/ppe_size_groups');
      if (sizeGroupSelect) {
        sizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
          groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      }

      const units = await API.get('/api/v1/units');
      if (unitSelect) {
        unitSelect.innerHTML = '<option value="">Не указана</option>' +
          units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');
      }
    } catch (err) {
      console.error('Ошибка загрузки справочников:', err);
    }
  }


  async function loadItem(isWsUpdate = false) {
    try {
      const item = await API.get(`/api/v1/ppe_items/${itemId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = item.version ?? '';
        return;
      }

      if (form.elements['name']) form.elements['name'].value = item.name ?? '';
      // Модель, артикул и класс защиты печатаются в графе 2 личной карточки
      if (form.elements['model']) form.elements['model'].value = item.model ?? '';
      if (form.elements['protection_class']) {
        form.elements['protection_class'].value = item.protection_class ?? '';
      }
      if (functionSelect) functionSelect.value = item.function_id ?? '';
      if (sizeGroupSelect) sizeGroupSelect.value = item.size_group_id ?? '';
      if (unitSelect) unitSelect.value = item.unit_id ?? '';
      if (versionInput) versionInput.value = item.version ?? '';

      isDirty = false;
      window.FormValidation.markClean(form);
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    await FormHelper.send(form, async (payload) => {
      payload.function_id = payload.function_id ? Number(payload.function_id) : null;
      payload.size_group_id = payload.size_group_id ? Number(payload.size_group_id) : null;
      payload.unit_id = payload.unit_id ? Number(payload.unit_id) : null;

      const updated = await API.put(`/api/v1/ppe_items/${itemId}`, payload);
      if (updated?.version != null) versionInput.value = updated.version;
      isDirty = false;
      window.showToast('Изменения сохранены', 'success');
    }, {
      button: btnSubmit,
      onConflict: () => FormHelper.showConflict(conflictAlert),
    });
  });

  WS.subscribe(async (data) => {
    if (data.event === 'item_updated' && data.item_id === itemId) {
      loadItem(true);
    }

    // Справочники могли поправить в соседней вкладке. Пересобираем списки,
    // сохраняя выбор: иначе перерисовка сбрасывала бы значения на «Не указана»
    if (['function_updated', 'size_group_updated', 'unit_updated'].includes(data.event)) {
      const selects = [functionSelect, sizeGroupSelect, unitSelect];
      const chosen = selects.map((el) => el?.value ?? '');
      await loadSelects();
      selects.forEach((el, index) => {
        if (el && chosen[index]) el.value = chosen[index];
      });
    }
  });

  loadSelects().then(() => loadItem());
})();

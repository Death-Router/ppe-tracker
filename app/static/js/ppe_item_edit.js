(() => {
  const itemId = window.ITEM_ID;
  const form = document.getElementById('item-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const selectCategory = document.getElementById('category_id');

  let isDirty = false;
  form.addEventListener('input', () => { isDirty = true; });

  // Загрузка выпадающего списка категорий
  async function loadCategories() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      selectCategory.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      selectCategory.innerHTML = '<option value="">Ошибка загрузки категорий</option>';
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadItem(isWsUpdate = false) {
    try {
      const item = await API.get(`/api/v1/ppe_items/${itemId}`);

      if (isWsUpdate && isDirty) {
        window.showToast('Наименование изменено другим пользователем.', 'warning');
        versionInput.value = item.version ?? '';
        return;
      }

      form.elements['name'].value = item.name ?? '';
      selectCategory.value = item.category_id ?? '';
      versionInput.value = item.version ?? '';
      
      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;
    
    try {
      await FormHelper.submit({
        form: form,
        apiUrl: `/api/v1/ppe_items/${itemId}`,
        conflictAlert: conflictAlert,
        onSuccess: (updated) => {
          if (updated?.version != null) versionInput.value = updated.version;
          isDirty = false;
          window.showToast('Изменения сохранены', 'success');
        }
      });
    } finally {
      btnSubmit.disabled = false;
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'item_updated' && data.item_id === itemId) {
      loadItem(true);
    }
  });

  // Инициализация: сначала грузим категории, затем данные
  loadCategories().then(() => loadItem());
})();
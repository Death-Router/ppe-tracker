// app/static/js/ppe_category_edit.js
(() => {
  const categoryId = window.CATEGORY_ID;
  const form = document.getElementById('category-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');

  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  // ---------- 1. Загрузка данных ----------
  async function loadCategory(isWsUpdate = false) {
    try {
      const cat = await API.get(`/api/v1/ppe_categories/${categoryId}`);
      
      if (isWsUpdate && isDirty) {
        window.showToast('Категория была изменена другим пользователем. Рекомендуем обновить страницу.', 'warning');
        versionInput.value = cat.version ?? '';
        return;
      }

      form.elements['name'].value = cat.name ?? '';
      form.elements['description'].value = cat.description ?? '';
      versionInput.value = cat.version ?? '';
      
      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка автоматически обновлена', 'info');

    } catch (err) {
      window.showToast(`Ошибка загрузки: ${err.message}`, 'danger');
    }
  }

  // ---------- 2. Отправка формы ----------
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;
    
    try {
      await FormHelper.submit({
        form: form,
        apiUrl: `/api/v1/ppe_categories/${categoryId}`,
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

  // ---------- 3. WebSocket ----------
  WS.subscribe((data) => {
    if (data.event === 'category_updated' && data.category_id === categoryId) {
      loadCategory(true);
    }
  });

  // Инициализация
  loadCategory();
})();
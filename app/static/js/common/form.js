// app/static/js/common/form.js
window.FormHelper = {
  // Превращает форму в объект { name: value, ... }
  serialize(form) {
    const data = {};
    const formData = new FormData(form);
    for (const [key, value] of formData.entries()) {
      // Преобразуем пустые строки в null
      data[key] = value.trim() === '' ? null : value.trim();
    }
    return data;
  },

  // Показывает желтый баннер «Данные устарели»
  showConflict(alertElement) {
    if (!alertElement) return;
    alertElement.classList.remove('d-none');
    alertElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
  },

  // Автоматическая привязка формы к API (PUT)
  async submit({ form, apiUrl, conflictAlert, onSuccess }) {
    event.preventDefault();
    if (conflictAlert) conflictAlert.classList.add('d-none');

    if (!form.checkValidity()) {
      form.classList.add('was-validated');
      return;
    }

    const payload = this.serialize(form);
    
    // Принудительно приводим version к числу (если есть)
    if (payload.version) payload.version = Number(payload.version);

    try {
      const updated = await API.put(apiUrl, payload);
      if (onSuccess) onSuccess(updated);
    } catch (err) {
      if (err.isConflict) {
        this.showConflict(conflictAlert);
      } else {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      }
    }
  }
};
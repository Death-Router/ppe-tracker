// app/static/js/common/form.js
window.FormHelper = {
  // Только цифры, не длиннее maxLength. Нужна для количеств: СИЗ считаются
  // штуками, а «-5» или «2,5» в карточке ломают остаток.
  digits(value, maxLength = 3) {
    return String(value ?? '').replace(/\D+/g, '').slice(0, maxLength);
  },

  // Маска на поле: чистит ввод на лету, при вставке и при потере фокуса.
  // Возвращает поле, чтобы вызывающий код мог продолжить настройку.
  onlyDigits(input, maxLength = 3) {
    if (!input) return null;

    const clean = () => {
      const digits = FormHelper.digits(input.value, maxLength);
      if (digits !== input.value) input.value = digits;
    };

    input.addEventListener('input', clean);
    input.addEventListener('blur', clean);
    // Автозаполнение и восстановление значения браузером не дают input —
    // поэтому чистим и сразу при подключении маски
    clean();
    return input;
  },

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

  // Отправка формы из модалки/страницы: кнопка блокируется на время запроса,
  // ошибка показывается тостом, валидация пересчитывается в любом случае.
  // Было 12 копий `try/catch/finally` вокруг `API.put/post` в списках.
  //
  //   await FormHelper.send(form, async (payload) => {
  //     await API.put(url, payload);
  //     window.showToast('Сохранено', 'success');
  //   }, { onSuccess: () => { hideModal(); form.reset(); load(); } });
  //
  // onConflict — свой обработчик для 409 (баннер «данные устарели»);
  // без него показывается обычный тост.
  // validate(payload) — проверка до запроса: вернуть текст проблемы или null
  // (например, «Выберите СИЗ из списка»); тогда запрос не уходит.
  // payload — готовый объект, если форма собирает его не через serialize
  // (norms_list: отдельное поле поиска СИЗ вместо select с name).
  async send(form, action, options = {}) {
    const {
      button = null,
      onSuccess = null,
      onConflict = null,
      validate = null,
      payload: given = null,
    } = options;
    const btn = button || form?.querySelector('button[type="submit"]');
    if (btn) btn.disabled = true;

    try {
      const data = given ?? this.serialize(form);
      if (validate) {
        const problem = validate(data);
        if (problem) {
          window.showToast(problem, 'danger');
          return;
        }
      }
      await action(data, form);
      if (onSuccess) onSuccess();
    } catch (err) {
      if (err.isConflict && onConflict) {
        onConflict(err);
      } else {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      }
    } finally {
      // refresh снова разблокирует кнопку, если форма валидна
      window.FormValidation.refresh(form);
    }
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
// --- Живая маска для полей ФИО ---
window.attachNameValidation = function (form, fieldNames) {
  if (!form || !window.Validators) return;
  fieldNames.forEach(name => {
    const el = form.elements[name];
    if (el) Validators.applyNameMask(el);
  });
};

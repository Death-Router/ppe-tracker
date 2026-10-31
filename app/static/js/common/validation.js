// app/static/js/common/validation.js
// Кнопка отправки формы активна только тогда, когда все обязательные поля заполнены.
// Работает для всех форм на странице, включая модальные окна.
window.FormValidation = (() => {
  const attached = new WeakSet();

  function submitButtons(form) {
    return form.querySelectorAll('button[type="submit"], [data-form-submit]');
  }

  function update(form) {
    if (!form) return true;
    const valid = form.checkValidity();
    submitButtons(form).forEach((btn) => { btn.disabled = !valid; });
    return valid;
  }

  function attach(form) {
    if (!form || attached.has(form)) return;
    attached.add(form);

    ['input', 'change', 'focusout'].forEach((eventName) => {
      form.addEventListener(eventName, () => update(form));
    });

    // После сброса значения меняются без события input
    form.addEventListener('reset', () => setTimeout(() => update(form), 0));

    // Страховка от отправки по Enter, когда кнопка недоступна
    form.addEventListener('submit', (event) => {
      if (!form.checkValidity()) {
        event.preventDefault();
        event.stopImmediatePropagation();
        update(form);
      }
    });

    update(form);
  }

  function scan(root = document) {
    root.querySelectorAll('form').forEach(attach);
  }

  // refresh() без аргумента пересчитывает все формы — вызывать после того,
  // как скрипт заполнил поля или подгрузил варианты в select программно.
  function refresh(form) {
    if (form) {
      attach(form);
      return update(form);
    }
    scan();
    document.querySelectorAll('form').forEach(update);
    return undefined;
  }

  document.addEventListener('DOMContentLoaded', () => {
    scan();
    // Браузер может автозаполнить поля уже после загрузки страницы
    setTimeout(() => refresh(), 300);
    setTimeout(() => refresh(), 1200);
  });

  return { attach, scan, refresh, update };
})();

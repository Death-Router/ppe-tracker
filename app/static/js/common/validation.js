// app/static/js/common/validation.js
// Кнопка отправки формы активна только тогда, когда все обязательные поля заполнены.
// Работает для всех форм на странице, включая модальные окна.
window.FormValidation = (() => {
  const attached = new WeakSet();
  // Снимок значений формы на момент открытия/загрузки. Кнопка отправки
  // активна, только если форма валидна И данные изменились: иначе
  // «Сохранить» нажимают «на всякий случай», и в API уходит пустой запрос.
  const baselines = new WeakMap();

  function submitButtons(form) {
    return form.querySelectorAll('button[type="submit"], [data-form-submit]');
  }

  function signature(form) {
    return window.FormHelper ? JSON.stringify(FormHelper.serialize(form)) : '';
  }

  function isDirty(form) {
    if (!baselines.has(form)) baselines.set(form, signature(form));
    return signature(form) !== baselines.get(form);
  }

  // Запомнить текущие значения как «исходные». Вызывать после программного
  // заполнения формы (режим редактирования) — иначе заполнение сразу считалось
  // бы правкой.
  function markClean(form) {
    if (!form) return;
    baselines.set(form, signature(form));
    update(form);
  }

  function update(form) {
    if (!form) return true;
    const valid = form.checkValidity();
    const dirty = isDirty(form);
    submitButtons(form).forEach((btn) => { btn.disabled = !valid || !dirty; });
    return valid;
  }

  function attach(form) {
    if (!form || attached.has(form)) return;
    attached.add(form);

    ['input', 'change', 'focusout'].forEach((eventName) => {
      form.addEventListener(eventName, () => update(form));
    });

    // После сброса значения меняются без события input; сброс = исходное
    // состояние, поэтому снимок обновляем и кнопку гасим
    form.addEventListener('reset', () => setTimeout(() => markClean(form), 0));

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

  return { attach, scan, refresh, update, markClean, isDirty };
})();

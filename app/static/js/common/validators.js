// app/static/js/common/validators.js
window.Validators = {
  // Разрешённые символы для ФИО: русские буквы и дефис
  nameAllowedChars: /[^А-Яа-яЁё-]/g,

  // Итоговый формат (для бэкенда / финальной проверки)
  // "Иванов", "Петрова-Водкина"
  nameFormat: /^[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)*$/,

  MAX_NAME_LEN: 32,

  // Применяет маску к input: фильтрует символы и управляет регистром
  applyNameMask(input) {
    if (!input) return;

    const format = (raw) => {
      // 1. Убираем всё, кроме русских букв и дефиса
      let s = String(raw).replace(this.nameAllowedChars, '');

      // 2. Разбиваем по дефису и приводим каждую часть к формату
      //    "иванов-петров" -> "Иванов-Петров"
      s = s.split('-').map(part => {
        if (!part) return '';
        // Первая буква — заглавная, остальные — строчные
        return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
      }).join('-');

      // 3. Обрезаем до MAX
      if (s.length > this.MAX_NAME_LEN) s = s.slice(0, this.MAX_NAME_LEN);

      // 4. Не даём начинать с дефиса и не допускаем двойных дефисов
      s = s.replace(/^-+/, '').replace(/--+/g, '-');

      return s;
    };

    const handler = () => {
      const before = input.value;
      const after = format(before);
      if (before !== after) {
        // Сохраняем позицию курсора максимально близко
        const pos = input.selectionStart ?? after.length;
        input.value = after;
        const shift = after.length - before.length;
        const newPos = Math.max(0, Math.min(after.length, pos + shift));
        try { input.setSelectionRange(newPos, newPos); } catch { /* ignore */ }
      }

      // Валидность: >= 2 символов и соответствует финальному формату
      const isValid = after.length >= 2 && this.nameFormat.test(after);
      input.classList.toggle('is-valid', isValid);
      input.classList.toggle('is-invalid', after.length > 0 && !isValid);
      input.setCustomValidity(isValid ? '' : (after.length < 2 ? 'Слишком короткое значение' : 'Недопустимый формат ФИО'));
    };

    // 'input' ловит и ввод с клавиатуры, и вставку из буфера
    input.addEventListener('input', handler);
    // На случай автозаполнения/программной установки
    input.addEventListener('change', handler);
    // Первый прогон — на случай, если значение уже было
    handler();
  },
};

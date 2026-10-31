// app/static/js/common/dom.js
// Общие DOM-хелперы. Экранирование одно на всё приложение: раньше в каждом
// файле была своя версия, и почти везде без кавычек — из-за этого имя с
// апострофом ломало разметку и открывало инъекцию в inline-обработчиках.
window.escapeHtml = function (value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
};

// Ширина выпадающего списка по самому длинному пункту.
// CSS width: auto у select не учитывает длину option — браузер отдаёт
// одинаковую ширину при любом содержимом, поэтому меряем текст на canvas
// и ограничиваем результат шириной контейнера.
window.fitSelectWidth = function (select) {
  if (!select) return;

  const style = window.getComputedStyle(select);
  const canvas = (window.__fitCanvas ||= document.createElement('canvas'));
  const ctx = canvas.getContext('2d');
  ctx.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;

  let longest = 0;
  for (const option of select.options) {
    const width = ctx.measureText(option.textContent || '').width;
    if (width > longest) longest = width;
  }

  // Отступы и место под стрелку
  const padding =
    parseFloat(style.paddingLeft) +
    parseFloat(style.paddingRight) +
    parseFloat(style.borderLeftWidth) +
    parseFloat(style.borderRightWidth);
  const arrow = 24;

  const available = select.parentElement
    ? select.parentElement.clientWidth
    : window.innerWidth;

  select.style.width = `${Math.min(Math.ceil(longest + padding + arrow), available)}px`;
};

// Подгоняем все помеченные списки и при изменении их содержимого
window.fitAllSelects = function (root = document) {
  root.querySelectorAll('[data-fit-width]').forEach(window.fitSelectWidth);
};


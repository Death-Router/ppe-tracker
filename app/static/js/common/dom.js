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

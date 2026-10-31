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

// true, если страница открыта внутри вкладки (iframe), а не как отдельный документ
window.isEmbedded = (() => {
  try {
    return window.self !== window.top;
  } catch {
    // Доступ к top закрыт — значит точно во фрейме
    return true;
  }
})();

// Переход на другую страницу из вкладки должен менять адрес всего приложения,
// иначе страница откроется внутри рамки и навбар продублируется.
window.goTo = function (url) {
  if (window.isEmbedded) {
    window.top.location.href = url;
  } else {
    window.location.href = url;
  }
};

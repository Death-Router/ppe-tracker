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

  // Ограничение — ширина панели фильтров, а не окна. clientWidth у только
  // что вставленного элемента бывает 0, поэтому берём ширину ближайшего
  // контейнера с ненулевой шириной.
  let available = 0;
  let node = select.parentElement;
  while (node && available === 0) {
    available = node.clientWidth;
    node = node.parentElement;
  }
  if (!available) available = document.documentElement.clientWidth;

  const wanted = Math.ceil(longest + padding + arrow);
  select.style.width = `${Math.min(wanted, available)}px`;
};

// Иерархический список подразделений: элемент, затем его дети с уровнем.
// Раньше эта функция копировалась в каждый скрипт, которому нужен select
// подразделений; теперь одна реализация на всё приложение.
window.buildDeptHierarchy = function (depts, parentId = null, level = 0) {
  let result = [];
  const children = depts.filter((d) => d.parent_id === parentId);
  children.sort((a, b) => a.name.localeCompare(b.name));

  for (const dept of children) {
    result.push({ ...dept, level });
    result = result.concat(window.buildDeptHierarchy(depts, dept.id, level + 1));
  }
  return result;
};

// Готовые <option> для select подразделения: «↳ » на каждом уровне вложенности,
// как в структуре и остальных формах. placeholder — первый пункт («Не указано»).
window.departmentOptionsHtml = function (depts, options = {}) {
  const { placeholder = null } = options;
  const items = window.buildDeptHierarchy(depts)
    .map((d) => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`)
    .join('');

  if (placeholder === null) return items;
  return `<option value="">${escapeHtml(placeholder)}</option>` + items;
};

// Кнопки в строках помечаются data-атрибутами (data-action, data-id,
// data-name), а не onclick: строка с кавычкой в названии ломала разметку и
// позволяла внедрить код (данные приходят из Excel-импорта).
//
// Делегирование кликов по кнопкам строки таблицы. Раньше в каждом списке был
// одинаковый пролог: closest('[data-action]'), Number(dataset.id),
// dataset.name, затем цепочка if по action.
// handlers: { action: (id, name, button) => … }
window.onRowAction = function (tbody, handlers) {
  if (!tbody) return;
  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('[data-action]');
    if (!btn || !tbody.contains(btn)) return;
    const handler = handlers[btn.dataset.action];
    if (handler) handler(Number(btn.dataset.id), btn.dataset.name || '', btn);
  });
};

// Строка-заглушка на всю таблицу: «пока нет», «ничего не найдено», ошибка.
// Текст экранируется здесь, передавайте «сырое» значение.
window.tableState = function (tbody, colspan, text, options = {}) {
  if (!tbody) return;
  const { error = false } = options;
  const cls = error ? 'state state--error' : 'state';
  tbody.innerHTML = `<tr><td colspan="${colspan}" class="${cls}">${escapeHtml(text)}</td></tr>`;
};

// Модалки Bootstrap: одна обёртка на всё приложение. Раньше в каждом файле
// было `bootstrap.Modal.getOrCreateInstance(el).show()` / `.hide()` и ручной
// поиск `.modal-title`; теперь это `ModalHelper`.
window.ModalHelper = {
  show(element) {
    if (element) bootstrap.Modal.getOrCreateInstance(element).show();
  },
  hide(element) {
    if (element) bootstrap.Modal.getOrCreateInstance(element).hide();
  },
  title(element) {
    return element?.querySelector('.modal-title') ?? null;
  },
  setTitle(element, text) {
    const target = this.title(element);
    if (target) target.textContent = text;
  },
};

// Вкладки Bootstrap: переключение по селектору, без ручного
// getOrCreateInstance(document.querySelector(...)).show() в каждой ветке.
window.TabHelper = {
  show(selector) {
    const tab = typeof selector === 'string' ? document.querySelector(selector) : selector;
    if (tab) bootstrap.Tab.getOrCreateInstance(tab).show();
  },
};

// Подгоняем все помеченные списки и при изменении их содержимого
window.fitAllSelects = function (root = document) {
  root.querySelectorAll('[data-fit-width]').forEach(window.fitSelectWidth);
};


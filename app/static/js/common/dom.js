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

// Даты приходят строками ISO («2026-11-05T00:00:00») или как date.
// Один набор форматтеров на приложение: раньше `formatDate` и `dateValue`
// жили в employees_list.js, а `split('T')[0]` дублировался по месту.

// «05.11.2026»; пустое значение — прочерк (или свой текст через empty)
window.formatDateRu = function (raw, empty = '—') {
  if (!raw) return empty;
  const [y, m, d] = String(raw).split('T')[0].split('-');
  return d ? `${d}.${m}.${y}` : String(raw);
};

// «2026-11-05» — формат для input[type=date]
window.dateInputValue = function (raw) {
  return raw ? String(raw).split('T')[0] : '';
};

// Сегодняшняя дата в том же формате. Через toISOString() нельзя: это UTC,
// и в Москве после полуночи он отдаёт вчерашний день (00:30 → 21:30 UTC).
window.todayIso = function () {
  const now = new Date();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${month}-${day}`;
};

// Срок носки: «1 год», «2 года», «5 лет»; «1 месяц», «3 месяца», «11 месяцев».
// Функция была в norms_list.js, но нигде не вызывалась — теперь общая.
window.formatPeriodRu = function (value, unit) {
  if (!value) return '—';
  const num = parseInt(value, 10);
  if (Number.isNaN(num)) return `${value} ${unit}`;

  const tails = {
    год: ['год', 'года', 'лет'],
    месяц: ['месяц', 'месяца', 'месяцев'],
  };
  const tail = tails[unit];
  if (!tail) return `${value} ${unit}`;

  const lastTwo = num % 100;
  const lastDigit = num % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return `${num} ${tail[2]}`;
  if (lastDigit === 1) return `${num} ${tail[0]}`;
  if (lastDigit >= 2 && lastDigit <= 4) return `${num} ${tail[1]}`;
  return `${num} ${tail[2]}`;
};

// Количество с единицей из справочника: «2 пары», «3 штуки», «5 комплектов».
// Склонение по трём формам; неизвестная единица отдаётся как есть.
window.formatQuantityRu = function (value, unitName) {
  const num = parseInt(String(value ?? ''), 10);
  const text = unitName ? String(unitName).trim() : '';
  if (Number.isNaN(num)) return `${value ?? ''} ${text}`.trim();
  if (!text) return String(num);

  const forms = {
    пара: ['пара', 'пары', 'пар'],
    штука: ['штука', 'штуки', 'штук'],
    шт: ['штука', 'штуки', 'штук'],
    'шт.': ['штука', 'штуки', 'штук'],
    комплект: ['комплект', 'комплекта', 'комплектов'],
    упаковка: ['упаковка', 'упаковки', 'упаковок'],
    литр: ['литр', 'литра', 'литров'],
    килограмм: ['килограмм', 'килограмма', 'килограммов'],
    рулон: ['рулон', 'рулона', 'рулонов'],
  };
  const tail = forms[text.toLowerCase()];
  if (!tail) return `${num} ${text}`;

  const lastTwo = num % 100;
  const lastDigit = num % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return `${num} ${tail[2]}`;
  if (lastDigit === 1) return `${num} ${tail[0]}`;
  if (lastDigit >= 2 && lastDigit <= 4) return `${num} ${tail[1]}`;
  return `${num} ${tail[2]}`;
};

// Модалки Bootstrap: одна обёртка на всё приложение. Раньше в каждом файле
// было `bootstrap.Modal.getOrCreateInstance(el).show()` / `.hide()` и ручной
// поиск `.modal-title`; теперь это `ModalHelper`.
window.ModalHelper = {
  show(element) {
    if (!element) return;
    // Формы внутри модалки к моменту показа уже заполнены (режим
    // редактирования) или сброшены (создание). Запоминаем это состояние как
    // исходное: «Сохранить» станет активной только после правки
    element.querySelectorAll('form').forEach((form) => {
      window.FormValidation?.markClean(form);
    });
    bootstrap.Modal.getOrCreateInstance(element).show();
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

// Закрытие формы с несохранёнными изменениями требует подтверждения.
// Работает и для модалок (Bootstrap шлёт hide.bs.modal, событие всплывает),
// и для ссылок «Закрыть» на страницах редактирования (data-dirty-close).
window.confirmDiscard = function (scope) {
  const forms = scope ? scope.querySelectorAll('form') : [];
  const dirty = [...forms].some((form) => window.FormValidation?.isDirty(form));
  if (!dirty) return true;
  return window.confirm('Есть несохранённые изменения. Закрыть без сохранения?');
};

document.addEventListener('hide.bs.modal', (event) => {
  if (!window.confirmDiscard(event.target)) event.preventDefault();
});

document.addEventListener('click', (event) => {
  const link = event.target.closest('[data-dirty-close]');
  if (!link) return;
  // Страница редактирования: форма одна, берём её из документа
  if (!window.confirmDiscard(document)) event.preventDefault();
});

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


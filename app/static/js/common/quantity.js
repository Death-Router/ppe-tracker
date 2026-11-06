// app/static/js/common/quantity.js
// Количества в карточке хранятся строками и приходят из разных мест (нормы,
// импорт, ручной ввод), поэтому разбор и правило остатка живут в одном месте:
// сервер проверяет то же самое, но сообщение должно совпадать с подсказкой.
window.Quantity = (() => {
  // «2», «2,5», « 2 » — числа; пусто — null; мусор («2 пары») — NaN
  function parse(raw) {
    const text = String(raw ?? '').replace(/\u00a0/g, ' ').trim();
    if (!text) return null;
    const value = Number(text.replace(',', '.'));
    return Number.isFinite(value) ? value : NaN;
  }

  // Остаток = выдано − возвращено. Возвращает текст подсказки и признак
  // ошибки: минус, ноль и буквы остатком не считаются.
  function describeReturn(issuedRaw, returnedRaw) {
    const issued = parse(issuedRaw);
    const returned = parse(returnedRaw);

    if (!Number.isFinite(issued) || issued <= 0) {
      return {
        text: `Количество выдачи «${issuedRaw}» не число — остаток не проверить, укажите количество цифрами`,
        isError: true,
      };
    }
    if (returned === null) {
      return { text: `Выдано ${issued} — вернуть можно не больше`, isError: false };
    }
    if (!Number.isFinite(returned) || returned <= 0) {
      return { text: 'Количество возврата — только цифры и больше нуля', isError: true };
    }
    if (returned > issued) {
      return {
        text: `Выдано ${issued}, возвращают ${returned}: остаток уйдёт в минус`,
        isError: true,
      };
    }
    return { text: `Выдано ${issued} · остаток ${issued - returned}`, isError: false };
  }

  return { parse, describeReturn };
})();

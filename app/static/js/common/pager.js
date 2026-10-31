// app/static/js/common/pager.js
// Рендер постраничной навигации. Разметку рисует один раз, дальше только
// подменяет кнопки — спискам остаётся вызвать Pager.render(...).
window.Pager = (() => {
  function pageNumbers(current, total, around = 2) {
    const pages = new Set([1, total]);
    for (let i = current - around; i <= current + around; i += 1) {
      if (i >= 1 && i <= total) pages.add(i);
    }
    const sorted = [...pages].sort((a, b) => a - b);

    const result = [];
    let prev = 0;
    for (const p of sorted) {
      if (prev && p - prev > 1) result.push('…');
      result.push(p);
      prev = p;
    }
    return result;
  }

  /**
   * @param {HTMLElement} container — куда рисовать
   * @param {{page:number,total:number,page_size:number,pages:number}} meta
   * @param {(page:number) => void} onGo — вызывается при клике
   */
  function render(container, meta, onGo) {
    if (!container) return;

    const { page = 1, total = 0, page_size = 0, pages = 0 } = meta || {};

    if (!total) {
      container.innerHTML = '';
      return;
    }

    const from = (page - 1) * page_size + 1;
    const to = Math.min(page * page_size, total);

    const buttons = pageNumbers(page, pages)
      .map((p) => {
        if (p === '…') return '<span class="pager__gap">…</span>';
        const current = p === page ? ' is-current' : '';
        return `<button type="button" class="pager__btn${current}" data-page="${p}">${p}</button>`;
      })
      .join('');

    container.innerHTML = `
      <div class="pager__info">${from}–${to} из ${total}</div>
      <div class="pager__buttons">
        <button type="button" class="pager__btn" data-page="${page - 1}" ${page <= 1 ? 'disabled' : ''}>‹</button>
        ${buttons}
        <button type="button" class="pager__btn" data-page="${page + 1}" ${page >= pages ? 'disabled' : ''}>›</button>
      </div>`;

    container.querySelectorAll('[data-page]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const target = Number(btn.dataset.page);
        if (!btn.disabled && target >= 1 && target <= pages && target !== page) {
          onGo(target);
        }
      });
    });
  }

  return { render };
})();

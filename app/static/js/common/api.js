// app/static/js/common/api.js
window.API = {
  // Токен CSRF из <meta name="csrf-token">; сервер сверяет его с сессией
  csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  },

  // Методы, которые меняют данные, требуют токен
  isUnsafe(method) {
    return !['GET', 'HEAD', 'OPTIONS'].includes((method || 'GET').toUpperCase());
  },

  async request(url, options = {}) {
    const method = (options.method || 'GET').toUpperCase();
    const csrfHeaders = this.isUnsafe(method)
      ? { 'X-CSRF-Token': this.csrfToken() }
      : {};

    const resp = await fetch(url, {
      cache: 'no-store',
      ...options,
      headers: {
        'Accept': 'application/json',
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...csrfHeaders,
        ...options.headers,
      },
    });

    // Если 409 — пробрасываем специальную ошибку
    if (resp.status === 409) {
      const err = new Error('Conflict');
      err.isConflict = true;
      throw err;
    }

    if (!resp.ok) {
      let detail = `HTTP ${resp.status}`;
      try {
        const body = await resp.json();
        detail = body.detail ?? detail;
      } catch { /* ignore */ }
      throw new Error(detail);
    }

    // Если ответ пустой (204) — возвращаем null
    if (resp.status === 204) return null;
    return resp.json();
  },

  get(url) { return this.request(url); },
  post(url, data) { return this.request(url, { method: 'POST', body: JSON.stringify(data) }); },
  put(url, data) { return this.request(url, { method: 'PUT', body: JSON.stringify(data) }); },
  delete(url) { return this.request(url, { method: 'DELETE' }); },
};

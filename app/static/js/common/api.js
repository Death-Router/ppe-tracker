// app/static/js/common/api.js
window.API = {
  async request(url, options = {}) {
    const resp = await fetch(url, {
      cache: 'no-store',
      ...options,
      headers: {
        'Accept': 'application/json',
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
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
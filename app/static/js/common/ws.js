// app/static/js/common/ws.js
window.WS = (() => {
  let ws = null;
  const listeners = new Set();

  function connect() {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    // Подключаемся к каналу 0 (общий)
    const url = `${proto}://${location.host}/ws/employees/0`;
    ws = new WebSocket(url);

    ws.onmessage = (event) => {
      let data;
      try { data = JSON.parse(event.data); } catch { return; }
      // Рассылаем событие всем подписчикам
      listeners.forEach(cb => cb(data));
    };

    ws.onclose = () => setTimeout(connect, 3000);
  }

  // Возвращаем объект с методом подписки
  return {
    subscribe(callback) {
      listeners.add(callback);
      if (!ws) connect(); // Подключаемся при первой подписке
      return () => listeners.delete(callback); // Возвращаем функцию отписки
    }
  };
})();
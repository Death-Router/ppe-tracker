// app/static/js/common/ws.js
window.WS = (() => {
  let ws = null;
  const listeners = new Set();

  // Нарастающая задержка переподключения: раньше при любой ошибке
  // (1006, 1011) клиент долбил сервер каждые 3 секунды, и лог заполнялся
  // десятками подключений, скрывая настоящие ошибки вроде 500.
  let attempt = 0;
  let timer = null;
  let stopped = false;

  const MAX_DELAY = 30000;
  const MAX_ATTEMPTS = 8;

  function connect() {
    if (stopped) return;

    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    // Подключаемся к каналу 0 (общий)
    const url = `${proto}://${location.host}/ws/employees/0`;

    try {
      ws = new WebSocket(url);
    } catch (err) {
      scheduleReconnect();
      return;
    }

    ws.onopen = () => {
      // Соединение восстановилось — счётчик неудач сбрасываем
      attempt = 0;
    };

    ws.onmessage = (event) => {
      let data;
      try { data = JSON.parse(event.data); } catch { return; }
      listeners.forEach((cb) => cb(data));
    };

    ws.onclose = (event) => {
      // 1008 — сервер отклонил соединение (нет авторизации):
      // переподключаться бессмысленно, это не восстановится само
      if (event.code === 1008) {
        stopped = true;
        return;
      }
      scheduleReconnect();
    };
  }

  function scheduleReconnect() {
    if (stopped || listeners.size === 0) return;

    attempt += 1;
    if (attempt > MAX_ATTEMPTS) {
      // Столько неудач подряд — дальше только шум в логах и нагрузка
      stopped = true;
      return;
    }

    // 3с, 6с, 12с, 24с, далее 30с
    const delay = Math.min(3000 * Math.pow(2, attempt - 1), MAX_DELAY);
    clearTimeout(timer);
    timer = setTimeout(connect, delay);
  }

  // Повторная попытка вручную: после очередной успешной операции с API
  function retry() {
    if (!stopped) return;
    stopped = false;
    attempt = 0;
    connect();
  }

  document.addEventListener('visibilitychange', () => {
    // Вернулись на вкладку — имеет смысл попробовать снова
    if (document.visibilityState === 'visible') retry();
  });

  return {
    subscribe(callback) {
      listeners.add(callback);
      if (!ws && !stopped) connect();
      return () => listeners.delete(callback);
    },
    retry,
  };
})();

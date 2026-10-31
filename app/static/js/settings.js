(() => {
  // Импорт сотрудников
  document.getElementById('import-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-result');
    const btn = document.getElementById('import-btn');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/employees', {
        method: 'POST',
        body: formData,
        headers: { 'X-CSRF-Token': API.csrfToken() },
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}, Обновлено: ${data.updated}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      window.FormValidation.refresh();
      btn.textContent = 'Загрузить';
    }
  });

  // Импорт СИЗ
  document.getElementById('import-items-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-items-result');
    const btn = form.querySelector('button[type="submit"]');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/ppe-items', {
        method: 'POST',
        body: formData,
        headers: { 'X-CSRF-Token': API.csrfToken() },
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт СИЗ выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      window.FormValidation.refresh();
      btn.textContent = 'Загрузить';
    }
  });

  // Импорт Норм
  document.getElementById('import-norms-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-norms-result');
    const btn = form.querySelector('button[type="submit"]');

    if (!fileInput.files.length) {
      window.showToast('Выберите файл', 'warning');
      return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
      const resp = await fetch('/api/v1/import/norms', {
        method: 'POST',
        body: formData,
        headers: { 'X-CSRF-Token': API.csrfToken() },
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

      let html = `<div class="alert alert-success">Создано: ${data.created}</div>`;
      if (data.errors && data.errors.length > 0) {
        html += `<div class="alert alert-warning mt-2">Ошибки: ${data.errors.join('<br>')}</div>`;
      }
      resultDiv.innerHTML = html;
      window.showToast('Импорт норм выполнен', 'success');
      form.reset();
    } catch (err) {
      resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
      window.showToast(err.message, 'danger');
    } finally {
      window.FormValidation.refresh();
      btn.textContent = 'Загрузить';
    }
  });
})();

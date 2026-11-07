(() => {
  // Импорт файла: три формы отличаются только адресом, полем результата и
  // подписью успеха. Раньше это были три копии по ~35 строк.
  //
  // `withUpdated` — импорт сотрудников отвечает ещё и счётчиком обновлённых.
  function setupImport({ formId, url, resultId, successText, withUpdated = false }) {
    const form = document.getElementById(formId);
    if (!form) return undefined;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const fileInput = form.querySelector('input[type="file"]');
      const resultDiv = document.getElementById(resultId);
      const btn = form.querySelector('button[type="submit"]');

      if (!fileInput.files.length) {
        window.showToast('Выберите файл', 'warning');
        return;
      }

      const formData = new FormData();
      formData.append('file', fileInput.files[0]);

      if (btn) {
        btn.disabled = true;
        btn.textContent = 'Загрузка...';
      }
      resultDiv.innerHTML = '';

      try {
        const resp = await fetch(url, {
          method: 'POST',
          body: formData,
          headers: { 'X-CSRF-Token': API.csrfToken() },
        });
        const data = await resp.json();
        if (!resp.ok) throw new Error(data.detail || 'Ошибка импорта');

        const counts = withUpdated
          ? `Создано: ${data.created}, Обновлено: ${data.updated}`
          : `Создано: ${data.created}`;
        let html = `<div class="alert alert-success">${counts}</div>`;
        if (data.errors && data.errors.length > 0) {
          // Тексты ошибок приходят из файла — экранируем, а не вставляем как HTML
          const listed = data.errors.map(escapeHtml).join('<br>');
          html += `<div class="alert alert-warning mt-2">Ошибки: ${listed}</div>`;
        }
        resultDiv.innerHTML = html;
        window.showToast(successText, 'success');
        form.reset();
      } catch (err) {
        resultDiv.innerHTML = `<div class="alert alert-danger">${escapeHtml(err.message)}</div>`;
        window.showToast(err.message, 'danger');
      } finally {
        window.FormValidation.refresh();
        if (btn) btn.textContent = 'Загрузить';
      }
    });
    return undefined;
  }

  setupImport({
    formId: 'import-form',
    url: '/api/v1/import/employees',
    resultId: 'import-result',
    successText: 'Импорт выполнен',
    withUpdated: true,
  });

  setupImport({
    formId: 'import-items-form',
    url: '/api/v1/import/ppe-items',
    resultId: 'import-items-result',
    successText: 'Импорт СИЗ выполнен',
  });

  setupImport({
    formId: 'import-norms-form',
    url: '/api/v1/import/norms',
    resultId: 'import-norms-result',
    successText: 'Импорт норм выполнен',
  });
})();


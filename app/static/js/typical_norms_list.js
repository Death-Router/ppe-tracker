// app/static/js/typical_norms_list.js
// Справочник типовых отраслевых норм: пункт приложения к Положению и описание.
// Пункт печатается в графе «Пункт Норм» личной карточки, поэтому справочник
// живёт на отдельной вкладке рядом с нормами выдачи, а не в модалке норм.
(() => {
  const tbody = document.querySelector('#typical-norms-table tbody');
  const searchInput = document.getElementById('search-input');
  const createForm = document.getElementById('create-form');
  const modalElement = document.getElementById('createModal');
  const modalTitle = modalElement ? modalElement.querySelector('.modal-title') : null;
  const submitBtn = createForm ? createForm.querySelector('button[type="submit"]') : null;

  let items = [];
  let editingId = null;
  let searchTerm = '';
  let searchTimer = null;

  async function loadItems() {
    try {
      // Поиск серверный: пунктов может быть много, и описание длинное
      const url = searchTerm
        ? `/api/v1/typical_norms/?search=${encodeURIComponent(searchTerm)}`
        : '/api/v1/typical_norms';
      items = await API.get(url);
      renderTable(items);
    } catch (err) {
      tbody.innerHTML =
        `<tr><td colspan="3" class="state state--error">Ошибка: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  function renderTable(list) {
    if (!list.length) {
      const text = searchTerm
        ? `По запросу «${escapeHtml(searchTerm)}» ничего не найдено`
        : 'Справочник пуст — добавьте пункты приложения к Положению';
      tbody.innerHTML = `<tr><td colspan="3" class="state">${text}</td></tr>`;
      return;
    }

    // Пункт и описание передаём через data-атрибуты: в onclick кавычка в
    // тексте ломала разметку (та же причина, что в остальных справочниках)
    tbody.innerHTML = list.map((n) => `
      <tr data-typical-id="${n.id}">
        <td class="cell-mono"><strong>${escapeHtml(n.clause)}</strong></td>
        <td title="${escapeHtml(n.description)}">${escapeHtml(n.description)}</td>
        <td class="col-actions">
          <button class="btn btn-icon" data-action="edit" data-id="${n.id}"
                  title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-icon btn-icon--danger" data-action="delete" data-id="${n.id}"
                  data-clause="${escapeHtml(n.clause)}" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  tbody.addEventListener('click', (event) => {
    const btn = event.target.closest('[data-action]');
    if (!btn) return;

    const id = Number(btn.dataset.id);
    if (btn.dataset.action === 'edit') window.editTypicalNorm(id);
    if (btn.dataset.action === 'delete') {
      window.deleteTypicalNorm(id, btn.dataset.clause || '');
    }
  });

  if (searchInput) {
    searchInput.addEventListener('input', (event) => {
      // Пауза после ввода: иначе на каждую букву уходит запрос в БД
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => {
        searchTerm = event.target.value.trim();
        loadItems();
      }, 300);
    });
  }

  window.openCreateModal = () => {
    if (!createForm || !modalTitle || !submitBtn) return;
    editingId = null;
    modalTitle.textContent = 'Новый пункт норм';
    submitBtn.textContent = 'Создать';
    createForm.reset();
    bootstrap.Modal.getOrCreateInstance(modalElement).show();
  };

  window.editTypicalNorm = async (id) => {
    try {
      // В отфильтрованном списке пункта может не быть — тогда дочитываем справочник
      let norm = items.find((n) => n.id === id);
      if (!norm) {
        const all = await API.get('/api/v1/typical_norms');
        norm = all.find((n) => n.id === id);
      }
      if (!norm) throw new Error('Пункт не найден');

      editingId = id;
      modalTitle.textContent = 'Редактирование пункта';
      submitBtn.textContent = 'Сохранить';
      createForm.elements['clause'].value = norm.clause;
      createForm.elements['description'].value = norm.description;

      bootstrap.Modal.getOrCreateInstance(modalElement).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  if (createForm) {
    createForm.addEventListener('submit', async (event) => {
      event.preventDefault();

      const payload = FormHelper.serialize(createForm);
      if (!payload.clause || !payload.description) {
        window.showToast('Заполните пункт и описание', 'danger');
        return;
      }

      if (submitBtn) submitBtn.disabled = true;
      try {
        if (editingId) {
          // Версия из загруженного списка — оптимистичная блокировка
          const current = items.find((n) => n.id === editingId);
          payload.version = current?.version ?? 1;
          await API.put(`/api/v1/typical_norms/${editingId}`, payload);
          window.showToast('Пункт обновлён', 'success');
        } else {
          await API.post('/api/v1/typical_norms/', payload);
          window.showToast('Пункт добавлен', 'success');
        }
        bootstrap.Modal.getOrCreateInstance(modalElement).hide();
        createForm.reset();
        loadItems();
      } catch (err) {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      } finally {
        if (submitBtn) submitBtn.disabled = false;
        window.FormValidation.refresh();
      }
    });
  }

  window.deleteTypicalNorm = async (id, clause) => {
    if (!confirm(`Удалить пункт «${clause}»?`)) return;
    try {
      await API.request(`/api/v1/typical_norms/${id}`, { method: 'DELETE' });
      window.showToast('Пункт удалён', 'success');
      loadItems();
    } catch (err) {
      // Сервер отказывает, если пункт указан в нормах выдачи, — причина в тексте
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  document.getElementById('btn-create')?.addEventListener('click', openCreateModal);

  loadItems();
})();

(() => {
  const posId = window.POS_ID;
  const form = document.getElementById('pos-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const deptSelect = document.getElementById('department_id');

  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  async function loadDepartments() {
    const depts = await API.get('/api/v1/departments');
    deptSelect.innerHTML = '<option value="">Выберите...</option>' + 
      depts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
  }


  async function loadPosition(isWsUpdate = false) {
    try {
      const pos = await API.get(`/api/v1/positions/${posId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = pos.version ?? '';
        return;
      }
      form.elements['name'].value = pos.name ?? '';
      deptSelect.value = pos.department_id ?? '';
      versionInput.value = pos.version ?? '';
      isDirty = false;
      window.FormValidation.refresh(form);
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;
    form.elements['department_id'].value = Number(deptSelect.value);
    
    try {
      await FormHelper.submit({
        form: form,
        apiUrl: `/api/v1/positions/${posId}`,
        conflictAlert: conflictAlert,
        onSuccess: (updated) => {
          if (updated?.version != null) versionInput.value = updated.version;
          isDirty = false;
          window.showToast('Изменения сохранены', 'success');
        }
      });
    } finally {
      window.FormValidation.refresh();
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'position_updated' && data.id === posId) {
      loadPosition(true);
    }
  });

  loadDepartments().then(() => loadPosition());
})();

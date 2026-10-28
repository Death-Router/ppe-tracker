(() => {
  const deptId = window.DEPT_ID;
  const form = document.getElementById('dept-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');

  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  async function loadDept(isWsUpdate = false) {
    try {
      const dept = await API.get(`/api/v1/departments/${deptId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = dept.version ?? '';
        return;
      }
      form.elements['name'].value = dept.name ?? '';
      versionInput.value = dept.version ?? '';
      isDirty = false;
      if (isWsUpdate) window.showToast('Карточка обновлена', 'info');
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  }

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    btnSubmit.disabled = true;
    try {
      await FormHelper.submit({
        form: form,
        apiUrl: `/api/v1/departments/${deptId}`,
        conflictAlert: conflictAlert,
        onSuccess: (updated) => {
          if (updated?.version != null) versionInput.value = updated.version;
          isDirty = false;
          window.showToast('Изменения сохранены', 'success');
        }
      });
    } finally {
      btnSubmit.disabled = false;
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'department_updated' && data.id === deptId) {
      loadDept(true);
    }
  });

  loadDept();
})();

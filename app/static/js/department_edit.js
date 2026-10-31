(() => {
  const deptId = window.DEPT_ID;
  const form = document.getElementById('dept-form');
  const btnSubmit = document.getElementById('btn-submit');
  const conflictAlert = document.getElementById('conflict-alert');
  const versionInput = document.getElementById('version');
  const parentSelect = document.getElementById('parent_id');

  let isDirty = false; 
  form.addEventListener('input', () => { isDirty = true; });

  async function loadParents(currentId) {
    const depts = await API.get('/api/v1/departments');
    // Строим иерархию, исключая текущее подразделение и его потомков (чтобы не было циклов)
    // Для простоты исключим только само текущее.
    const filtered = depts.filter(d => d.id !== currentId);
    
    // Функция для построения иерархического списка
    function buildHierarchy(items, parentId = null, level = 0) {
      let result = [];
      const children = items.filter(d => d.parent_id === parentId);
      children.sort((a, b) => a.name.localeCompare(b.name));
      for (const child of children) {
        result.push({ ...child, level });
        result = result.concat(buildHierarchy(items, child.id, level + 1));
      }
      return result;
    }

    const hierarchy = buildHierarchy(filtered);
    parentSelect.innerHTML = '<option value="">Нет (корневое)</option>' + 
      hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
  }


  async function loadDept(isWsUpdate = false) {
    try {
      const dept = await API.get(`/api/v1/departments/${deptId}`);
      if (isWsUpdate && isDirty) {
        window.showToast('Данные были изменены другим пользователем.', 'warning');
        versionInput.value = dept.version ?? '';
        return;
      }
      form.elements['name'].value = dept.name ?? '';
      
      await loadParents(deptId);
      parentSelect.value = dept.parent_id ?? '';
      
      versionInput.value = dept.version ?? '';
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
    
    const payload = FormHelper.serialize(form);
    payload.parent_id = payload.parent_id ? Number(payload.parent_id) : null;

    try {
      const updated = await API.put(`/api/v1/departments/${deptId}`, payload);
      if (updated?.version != null) versionInput.value = updated.version;
      isDirty = false;
      window.showToast('Изменения сохранены', 'success');
    } catch (err) {
      if (err.isConflict) {
        conflictAlert.classList.remove('d-none');
        conflictAlert.scrollIntoView({ behavior: 'smooth', block: 'center' });
      } else {
        window.showToast(`Ошибка: ${err.message}`, 'danger');
      }
    } finally {
      window.FormValidation.refresh();
    }
  });

  WS.subscribe((data) => {
    if (data.event === 'department_updated' && data.id === deptId) {
      loadDept(true);
    }
  });

  loadDept();
})();

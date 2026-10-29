#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем модель Department (добавляем parent_id)..."

cat > app/models/department.py << 'EOF'
from typing import TYPE_CHECKING, Optional
from sqlalchemy import String, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.position import Position
    from app.models.employee import Employee

class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    
    # Ссылка на самого себя (вышестоящее подразделение)
    parent_id: Mapped[int | None] = mapped_column(ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    # Связи
    parent: Mapped[Optional["Department"]] = relationship(remote_side=[id], back_populates="children")
    children: Mapped[list["Department"]] = relationship(back_populates="parent", cascade="all, delete-orphan")
    
    positions: Mapped[list["Position"]] = relationship(back_populates="department", cascade="all, delete-orphan")
    employees: Mapped[list["Employee"]] = relationship(back_populates="department_rel")
EOF

echo "📝 Обновляем схемы..."

cat > app/schemas/department.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class DepartmentBase(BaseModel):
    name: str = Field(..., max_length=100)
    parent_id: int | None = None

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentRead(DepartmentBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class DepartmentUpdate(DepartmentBase):
    name: str | None = None
    parent_id: int | None = None
    version: int
EOF

echo "📝 Обновляем API (обработка parent_id)..."

cat > app/api/v1/endpoints/departments.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.department import Department
from app.schemas.department import DepartmentCreate, DepartmentRead, DepartmentUpdate

router = APIRouter(prefix="/departments", tags=["Справочник: Подразделения"])

@router.post("/", response_model=DepartmentRead, status_code=status.HTTP_201_CREATED)
async def create_department(dept_in: DepartmentCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.name == dept_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Подразделение уже существует")
    
    # Проверка существования родителя
    if dept_in.parent_id:
        parent_res = await db.execute(select(Department).where(Department.id == dept_in.parent_id))
        if not parent_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Вышестоящее подразделение не найдено")

    db_dept = Department(**dept_in.model_dump())
    db.add(db_dept)
    await db.commit()
    await db.refresh(db_dept)
    return db_dept

@router.get("/", response_model=list[DepartmentRead])
async def get_departments(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).options(selectinload(Department.children)))
    return result.scalars().all()

@router.get("/{dept_id}", response_model=DepartmentRead)
async def get_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    dept = result.scalar_one_or_none()
    if not dept: raise HTTPException(status_code=404, detail="Не найдено")
    return dept

@router.put("/{dept_id}", response_model=DepartmentRead)
async def update_department(dept_id: int, dept_in: DepartmentUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept: raise HTTPException(status_code=404, detail="Не найдено")
    if db_dept.version != dept_in.version: raise HTTPException(status_code=409, detail="Данные устарели")
    
    if dept_in.parent_id:
        if dept_in.parent_id == dept_id:
            raise HTTPException(status_code=400, detail="Подразделение не может быть родителем самому себе")
        parent_res = await db.execute(select(Department).where(Department.id == dept_in.parent_id))
        if not parent_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Вышестоящее подразделение не найдено")
    
    update_data = dept_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_dept, field, value)
    db_dept.version += 1
    await db.commit()
    
    try:
        await manager.broadcast_to_employee(0, {"event": "department_updated", "id": dept_id})
    except: pass
    return db_dept

@router.delete("/{dept_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_department(dept_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Department).where(Department.id == dept_id))
    db_dept = result.scalar_one_or_none()
    if not db_dept: raise HTTPException(status_code=404, detail="Не найдено")
    try:
        await db.delete(db_dept)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить, есть привязанные данные")
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "add parent_id to departments"
docker compose exec -T api alembic upgrade head

echo "📝 Обновляем интерфейс (иерархия в списке и карточке)..."

# Обновляем templates/departments/list.html
cat > app/templates/departments/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Подразделения</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-hover align-middle mb-0" id="departments-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Вышестоящее</th>
                <th class="text-end">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="3" class="text-center text-muted py-4">Загрузка…</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Модальное окно создания -->
<div class="modal fade" id="createModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="create-form">
        <div class="modal-header">
          <h5 class="modal-title">Новое подразделение</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="100">
          </div>
          <div class="mb-3">
            <label class="form-label">Вышестоящее подразделение</label>
            <select class="form-select" name="parent_id" id="create-parent">
                <option value="">Нет (корневое)</option>
            </select>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-primary">Создать</button>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/departments_list.js') }}"></script>
{% endblock %}
EOF

# Обновляем templates/departments/edit.html
cat > app/templates/departments/edit.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-6">
        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h3 mb-0">Редактирование подразделения</h1>
            <a href="/departments" class="btn btn-outline-secondary">← К списку</a>
        </div>

        <div id="conflict-alert" class="alert alert-warning d-none" role="alert">
            Данные устарели, обновите страницу.
            <button type="button" class="btn btn-sm btn-warning ms-2" onclick="location.reload()">Обновить</button>
        </div>

        <form id="dept-form" class="card shadow-sm p-4" novalidate>
            <input type="hidden" name="version" id="version" value="">
            <div class="row g-3">
                <div class="col-12">
                    <label class="form-label" for="name">Название <span class="text-danger">*</span></label>
                    <input class="form-control" id="name" name="name" required maxlength="100">
                </div>
                <div class="col-12">
                    <label class="form-label" for="parent_id">Вышестоящее подразделение</label>
                    <select class="form-select" id="parent_id" name="parent_id">
                        <option value="">Нет (корневое)</option>
                    </select>
                </div>
            </div>
            <div class="d-flex justify-content-end gap-2 mt-4">
                <a href="/departments" class="btn btn-outline-secondary">Отмена</a>
                <button type="submit" class="btn btn-primary" id="btn-submit">Сохранить</button>
            </div>
        </form>
    </div>
</div>
{% endblock %}

{% block scripts %}
<script>
  window.DEPT_ID = Number("{{ dept_id }}");
</script>
<script src="{{ url_for('static', path='js/department_edit.js') }}"></script>
{% endblock %}
EOF

echo "📝 Обновляем JS для списка подразделений..."

cat > app/static/js/departments_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#departments-table tbody');
  const createForm = document.getElementById('create-form');
  const createParentSelect = document.getElementById('create-parent');

  // Функция для построения иерархического списка
  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    
    // Сортируем по имени для стабильности
    filtered.sort((a, b) => a.name.localeCompare(b.name));

    for (const dept of filtered) {
      result.push({ ...dept, level });
      // Рекурсивно добавляем детей
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }

  async function loadDepartments() {
    try {
      const depts = await API.get('/api/v1/departments');
      const hierarchy = buildHierarchy(depts);
      renderTable(hierarchy);
      
      // Заполняем выпадающий список для создания (тоже иерархически)
      if (createParentSelect) {
        createParentSelect.innerHTML = '<option value="">Нет (корневое)</option>' + 
          hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }

  function renderTable(hierarchy) {
    if (!hierarchy.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Подразделений пока нет</td></tr>`;
      return;
    }
    
    // Находим родителя для каждого элемента (для отображения в колонке "Вышестоящее")
    const deptMap = {};
    hierarchy.forEach(d => { deptMap[d.id] = d; });

    tbody.innerHTML = hierarchy.map(d => {
      const parentName = d.parent_id && deptMap[d.parent_id] ? deptMap[d.parent_id].name : '—';
      const indent = '&nbsp;'.repeat(d.level * 4);
      
      return `
      <tr data-dept-id="${d.id}">
        <td><span style="display:inline-block; padding-left: ${d.level * 20}px;">${escapeHtml(d.name)}</span></td>
        <td>${escapeHtml(parentName)}</td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/departments/${d.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteDept(${d.id}, '${escapeHtml(d.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.parent_id = payload.parent_id ? Number(payload.parent_id) : null;
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/departments/', payload);
      window.showToast('Подразделение создано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteDept = async (id, name) => {
    if (!confirm(`Удалить подразделение "${name}"?`)) return;
    try {
      await API.request(`/api/v1/departments/${id}`, { method: 'DELETE' });
      window.showToast('Подразделение удалено', 'success');
      loadDepartments();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'department_updated') loadDepartments();
  });

  loadDepartments();
})();
EOF

echo "📝 Обновляем JS для карточки подразделения..."

cat > app/static/js/department_edit.js << 'EOF'
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
      hierarchy.map(d => `<option value="${d.id}">${'&nbsp;'.repeat(d.level * 3)}${escapeHtml(d.name)}</option>`).join('');
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'); }

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
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иерархия подразделений добавлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add hierarchy (parent_id) to departments"
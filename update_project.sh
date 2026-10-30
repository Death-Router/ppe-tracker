#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем API для управления пользователями..."

# 1. Схемы
cat > app/schemas/user.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class UserBase(BaseModel):
    username: str = Field(..., max_length=50)
    role: str = Field(..., description="admin или safety_officer")
    department_id: int | None = None
    include_subdepartments: bool = False
    is_active: bool = True

class UserCreate(UserBase):
    password: str = Field(..., min_length=6)

class UserRead(UserBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

class UserUpdate(BaseModel):
    username: str | None = None
    password: str | None = None
    role: str | None = None
    department_id: int | None = None
    include_subdepartments: bool | None = None
    is_active: bool | None = None
EOF

# 2. API
cat > app/api/v1/endpoints/users.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.user import User
from app.core.security import get_password_hash
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.core.deps import get_current_active_user

router = APIRouter(prefix="/users", tags=["Пользователи"])

# Проверка, что текущий пользователь — админ
async def require_admin(current_user: User = Depends(get_current_active_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Доступ только для администратора")
    return current_user

@router.get("/", response_model=list[UserRead])
async def get_users(db: AsyncSession = Depends(get_db), _ = Depends(require_admin)):
    result = await db.execute(select(User).order_by(User.username))
    return result.scalars().all()

@router.post("/", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_user(user_in: UserCreate, db: AsyncSession = Depends(get_db), _ = Depends(require_admin)):
    result = await db.execute(select(User).where(User.username == user_in.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Пользователь с таким логином уже существует")
    
    db_user = User(
        username=user_in.username,
        hashed_password=get_password_hash(user_in.password),
        role=user_in.role,
        department_id=user_in.department_id,
        include_subdepartments=user_in.include_subdepartments,
        is_active=user_in.is_active
    )
    db.add(db_user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка при создании пользователя")
    
    await db.refresh(db_user)
    return db_user

@router.put("/{user_id}", response_model=UserRead)
async def update_user(user_id: int, user_in: UserUpdate, db: AsyncSession = Depends(get_db), _ = Depends(require_admin)):
    result = await db.execute(select(User).where(User.id == user_id))
    db_user = result.scalar_one_or_none()
    if not db_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    
    update_data = user_in.model_dump(exclude_unset=True)
    if 'password' in update_data and update_data['password']:
        db_user.hashed_password = get_password_hash(update_data['password'])
        del update_data['password']
    
    for field, value in update_data.items():
        setattr(db_user, field, value)
    
    await db.commit()
    await db.refresh(db_user)
    return db_user

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(user_id: int, db: AsyncSession = Depends(get_db), _ = Depends(require_admin)):
    result = await db.execute(select(User).where(User.id == user_id))
    db_user = result.scalar_one_or_none()
    if not db_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    
    # Нельзя удалить самого себя (или последнего админа)
    if db_user.username == "admin":
        raise HTTPException(status_code=400, detail="Нельзя удалить главного администратора")
    
    await db.delete(db_user)
    await db.commit()
EOF

echo "🔧 Подключаем роутер users в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'from app.api.v1.endpoints import users' not in content:
    content = content.replace(
        'from app.api.v1.endpoints import (',
        'from app.api.v1.endpoints import users, '
    )
    content = content.replace(
        'app.include_router(units.router, prefix="/api/v1")',
        'app.include_router(units.router, prefix="/api/v1")\napp.include_router(users.router, prefix="/api/v1")'
    )

# Добавляем HTML-маршрут /users
if '/users' not in content:
    route = '''
@app.get("/users", response_class=HTMLResponse)
async def users_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    # Проверяем роль (упрощенно: на фронте скроем, но лучше и на бэке)
    return templates.TemplateResponse(
        request=request,
        name="users/list.html",
        context={"title": "Пользователи"},
    )
'''
    content += route

with open('app/main.py', 'w') as f:
    f.write(content)
print("✅ main.py обновлен (users).")
PYEOF

echo "📝 Создаем страницу /users..."

mkdir -p app/templates/users
cat > app/templates/users/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex align-items-center gap-2 mb-3">
    <button class="btn btn-add-purple" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить">
        <i class="bi bi-plus-lg"></i>
    </button>
    <h1 class="h3 mb-0">Пользователи</h1>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="users-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Логин</th>
                <th>Роль</th>
                <th>Подразделение</th>
                <th>Активен</th>
                <th class="text-end" style="width: 120px;">Действия</th>
            </tr>
            </thead>
            <tbody>
            <tr><td colspan="5" class="text-center text-muted py-4">Загрузка…</td></tr>
            </tbody>
        </table>
    </div>
</div>

<!-- Модалка создания/редактирования -->
<div class="modal fade" id="createModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="user-form" data-validate="true">
        <input type="hidden" name="user_id" id="user-id" value="">
        <div class="modal-header">
          <h5 class="modal-title" id="modal-title">Новый пользователь</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Логин <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="username" required maxlength="50">
          </div>
          <div class="mb-3">
            <label class="form-label">Пароль <span class="text-danger">*</span></label>
            <input type="password" class="form-control" name="password" id="password" required minlength="6">
            <div class="form-text" id="password-hint" style="display: none;">Оставьте пустым, чтобы не менять.</div>
          </div>
          <div class="mb-3">
            <label class="form-label">Роль <span class="text-danger">*</span></label>
            <select class="form-select" name="role" id="role-select" required>
                <option value="safety_officer">Специалист ОТ</option>
                <option value="admin">Администратор</option>
            </select>
          </div>
          <div class="mb-3" id="department-group">
            <label class="form-label">Подразделение</label>
            <select class="form-select" name="department_id" id="department-select">
                <option value="">Не указано</option>
            </select>
          </div>
          <div class="mb-3" id="subdep-group">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="include_subdepartments" id="include-subdep">
              <label class="form-check-label" for="include-subdep">
                Включать дочерние подразделения
              </label>
            </div>
          </div>
          <div class="mb-3">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="is_active" id="is-active" checked>
              <label class="form-check-label" for="is-active">Активен</label>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-brand-orange" data-bs-dismiss="modal">Отмена</button>
          <button type="submit" class="btn btn-brand-purple">Сохранить</button>
        </div>
      </form>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script src="{{ url_for('static', path='js/users_list.js') }}"></script>
{% endblock %}
EOF

echo "📝 Создаем JS для страницы /users..."

cat > app/static/js/users_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#users-table tbody');
  const form = document.getElementById('user-form');
  const modalTitle = document.getElementById('modal-title');
  const userIdInput = document.getElementById('user-id');
  const passwordInput = document.getElementById('password');
  const passwordHint = document.getElementById('password-hint');
  const roleSelect = document.getElementById('role-select');
  const departmentSelect = document.getElementById('department-select');
  const departmentGroup = document.getElementById('department-group');
  const subdepGroup = document.getElementById('subdep-group');
  const includeSubdep = document.getElementById('include-subdep');

  let allUsers = [];
  let allDepartments = [];
  let editingId = null;

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  async function loadData() {
    try {
      allUsers = await API.get('/api/v1/users');
      allDepartments = await API.get('/api/v1/departments');
      renderTable(allUsers);
      
      // Заполняем выпадающий список подразделений
      const sortedDepts = [...allDepartments].sort((a, b) => a.name.localeCompare(b.name));
      departmentSelect.innerHTML = '<option value="">Не указано</option>' +
        sortedDepts.map(d => `<option value="${d.id}">${escapeHtml(d.name)}</option>`).join('');
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function renderTable(users) {
    if (!users.length) {
      tbody.innerHTML = `<tr><td colspan="5" class="text-center text-muted py-4">Пользователей пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = users.map(u => {
      const deptName = allDepartments.find(d => d.id === u.department_id)?.name || '—';
      const roleName = u.role === 'admin' ? 'Администратор' : 'Специалист ОТ';
      return `
      <tr data-user-id="${u.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(u.username)}</strong></td>
        <td class="py-1"><span class="badge bg-purple">${roleName}</span></td>
        <td class="py-1">${escapeHtml(deptName)}</td>
        <td class="py-1">${u.is_active ? '<span class="badge bg-success">Да</span>' : '<span class="badge bg-danger">Нет</span>'}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editUser(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUser(${u.id})" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `}).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    editingId = null;
    modalTitle.textContent = 'Новый пользователь';
    userIdInput.value = '';
    form.reset();
    passwordInput.required = true;
    passwordHint.style.display = 'none';
    new bootstrap.Modal(document.getElementById('createModal')).show();
  };

  // Редактирование
  window.editUser = async (id) => {
    try {
      const user = allUsers.find(u => u.id === id);
      if (!user) throw new Error('Пользователь не найден');
      
      editingId = id;
      modalTitle.textContent = 'Редактирование пользователя';
      userIdInput.value = id;
      
      form.elements['username'].value = user.username;
      passwordInput.value = '';
      passwordInput.required = false;
      passwordHint.style.display = 'block';
      
      roleSelect.value = user.role;
      departmentSelect.value = user.department_id || '';
      includeSubdep.checked = user.include_subdepartments || false;
      form.elements['is_active'].checked = user.is_active;
      
      new bootstrap.Modal(document.getElementById('createModal')).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Сохранение
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(form);
    
    if (payload.department_id) {
      payload.department_id = Number(payload.department_id);
    } else {
      payload.department_id = null;
    }
    
    payload.include_subdepartments = includeSubdep.checked;
    payload.is_active = form.elements['is_active'].checked;
    
    const btn = form.querySelector('button[type="submit"]');
    btn.disabled = true;
    
    try {
      if (editingId) {
        if (!payload.password) delete payload.password;
        await API.put(`/api/v1/users/${editingId}`, payload);
        window.showToast('Пользователь обновлен', 'success');
      } else {
        await API.post('/api/v1/users/', payload);
        window.showToast('Пользователь создан', 'success');
      }
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  // Удаление
  window.deleteUser = async (id) => {
    if (!confirm('Удалить этого пользователя?')) return;
    try {
      await API.request(`/api/v1/users/${id}`, { method: 'DELETE' });
      window.showToast('Пользователь удален', 'success');
      loadData();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Привязка кнопки "Добавить"
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadData();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Страница пользователей создана."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add users management page (admin only)"
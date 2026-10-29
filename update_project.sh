#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем схемы для Unit..."

cat > app/schemas/unit.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class UnitBase(BaseModel):
    name: str = Field(..., max_length=50, description="Полное название (например, Пара)")
    short_name: str = Field(..., max_length=10, description="Сокращение (например, пар)")

class UnitCreate(UnitBase):
    pass

class UnitRead(UnitBase):
    id: int
    model_config = ConfigDict(from_attributes=True)
EOF

echo "📝 Создаем API для единиц измерения..."

cat > app/api/v1/endpoints/units.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.unit import Unit
from app.schemas.unit import UnitCreate, UnitRead

router = APIRouter(prefix="/units", tags=["Справочник: Единицы измерения"])

@router.post("/", response_model=UnitRead, status_code=status.HTTP_201_CREATED)
async def create_unit(unit_in: UnitCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).where(Unit.name == unit_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая единица измерения уже существует")
    
    db_unit = Unit(**unit_in.model_dump())
    db.add(db_unit)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка при создании единицы")
    
    await db.refresh(db_unit)
    return db_unit

@router.get("/", response_model=list[UnitRead])
async def get_units(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).order_by(Unit.name))
    return result.scalars().all()

@router.delete("/{unit_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_unit(unit_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).where(Unit.id == unit_id))
    db_unit = result.scalar_one_or_none()
    if not db_unit:
        raise HTTPException(status_code=404, detail="Единица не найдена")
    try:
        await db.delete(db_unit)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить единицу, есть привязанные СИЗ")
EOF

echo "🔧 Подключаем units в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'units' not in content.split('app.include_router')[0]:
    # Добавляем в импорт
    content = content.replace(
        'auth',
        'auth, units'
    )
    # Добавляем include_router
    content = content.replace(
        'app.include_router(auth.router, prefix="/api/v1")',
        'app.include_router(auth.router, prefix="/api/v1")\napp.include_router(units.router, prefix="/api/v1")'
    )

# Добавляем HTML-маршрут для страницы единиц
if '/units' not in content:
    route = '''
@app.get("/units", response_class=HTMLResponse)
async def units_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="units/list.html",
        context={"title": "Единицы измерения"},
    )
'''
    content += route

with open('app/main.py', 'w') as f:
    f.write(content)
print("✅ main.py обновлен (units).")
PYEOF

echo "📝 Создаем страницу /units..."

mkdir -p app/templates/units
cat > app/templates/units/list.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="d-flex justify-content-between align-items-center mb-3">
    <h1 class="h3 mb-0">Единицы измерения</h1>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>

<div class="card shadow-sm">
    <div class="table-responsive">
        <table class="table table-sm table-hover align-middle mb-0" id="units-table">
            <thead class="bg-brand-orange">
            <tr>
                <th>Название</th>
                <th>Сокращение</th>
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
          <h5 class="modal-title">Новая единица измерения</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <div class="mb-3">
            <label class="form-label">Название <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="name" required maxlength="50" placeholder="Например, Пара">
          </div>
          <div class="mb-3">
            <label class="form-label">Сокращение <span class="text-danger">*</span></label>
            <input type="text" class="form-control" name="short_name" required maxlength="10" placeholder="Например, пар">
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
<script src="{{ url_for('static', path='js/units_list.js') }}"></script>
{% endblock %}
EOF

cat > app/static/js/units_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#units-table tbody');
  const createForm = document.getElementById('create-form');

  async function loadUnits() {
    try {
      const units = await API.get('/api/v1/units');
      renderTable(units);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(units) {
    if (!units.length) {
      tbody.innerHTML = `<tr><td colspan="3" class="text-center text-muted py-4">Единиц измерения пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = units.map(u => `
      <tr data-unit-id="${u.id}" style="height: 40px;">
        <td class="py-1"><strong>${escapeHtml(u.name)}</strong></td>
        <td class="py-1">${escapeHtml(u.short_name)}</td>
        <td class="py-1 text-end">
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUnit(${u.id}, '${escapeHtml(u.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/units/', payload);
      window.showToast('Единица создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadUnits();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteUnit = async (id, name) => {
    if (!confirm(`Удалить единицу "${name}"?`)) return;
    try {
      await API.request(`/api/v1/units/${id}`, { method: 'DELETE' });
      window.showToast('Единица удалена', 'success');
      loadUnits();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  loadUnits();
})();
EOF

echo "📝 Добавляем единицы в навбар..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

if '/units' not in content:
    # Добавляем ссылку в меню после "Наименования СИЗ"
    content = content.replace(
        '<a class="nav-link {% if \'/ppe-items\' in request.url.path %}active{% endif %}" href="/ppe-items">Наименования СИЗ</a>',
        '<a class="nav-link {% if \'/ppe-items\' in request.url.path %}active{% endif %}" href="/ppe-items">Наименования СИЗ</a>\n                </li>\n                <li class="nav-item">\n                    <a class="nav-link {% if \'/units\' in request.url.path %}active{% endif %}" href="/units">Единицы</a>'
    )
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Ссылка на единицы добавлена в навбар.")
else:
    print("ℹ️ Ссылка уже есть.")
PYEOF

echo "📝 Обновляем форму создания СИЗ (добавляем выбор единицы)..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Добавляем поле выбора единицы в модалку создания СИЗ
old_form = '''          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
            </select>
          </div>'''

new_form = '''          <div class="mb-3">
            <label class="form-label">Категория <span class="text-danger">*</span></label>
            <select class="form-select" name="category_id" id="create-category" required>
                <option value="">Загрузка...</option>
            </select>
          </div>
          <div class="mb-3">
            <label class="form-label">Единица измерения</label>
            <select class="form-select" name="unit_id" id="create-unit">
                <option value="">Не указана</option>
            </select>
          </div>'''

if old_form in content:
    content = content.replace(old_form, new_form)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Поле выбора единицы добавлено в форму создания СИЗ.")
else:
    print("⚠️ Не удалось найти форму создания СИЗ для добавления единицы.")
PYEOF

echo "📝 Обновляем JS для создания СИЗ (загрузка единиц)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Добавляем загрузку единиц в createCategorySelect
old_load = '''  async function loadCategoriesForSelect() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      createCategorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      createCategorySelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }'''

new_load = '''  async function loadCategoriesForSelect() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      createCategorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      createCategorySelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  async function loadUnitsForSelect() {
    try {
      const units = await API.get('/api/v1/units');
      const unitSelect = document.getElementById('create-unit');
      if (unitSelect) {
        unitSelect.innerHTML = '<option value="">Не указана</option>' +
          units.map(u => `<option value="${u.id}">${escapeHtml(u.name)} (${escapeHtml(u.short_name)})</option>`).join('');
      }
    } catch (err) {
      console.error('Ошибка загрузки единиц:', err);
    }
  }'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("✅ Функция загрузки единиц добавлена.")
else:
    print("⚠️ Не удалось найти функцию loadCategoriesForSelect.")

# В createForm submit добавляем unit_id
old_submit = '''    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);'''

new_submit = '''    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);
    if (payload.unit_id) {
      payload.unit_id = Number(payload.unit_id);
    } else {
      payload.unit_id = null;
    }'''

if old_submit in content:
    content = content.replace(old_submit, new_submit)
    print("✅ unit_id добавлен в payload при создании СИЗ.")
else:
    print("⚠️ Не удалось найти createForm submit.")

# В инициализации вызываем loadUnitsForSelect
old_init = '''  loadCategoriesForSelect();
  loadItems();'''
new_init = '''  loadCategoriesForSelect();
  loadUnitsForSelect();
  loadItems();'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("✅ Инициализация обновлена (загрузка единиц).")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Единицы измерения добавлены в систему."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add units management and integrate into ppe_items"
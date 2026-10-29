#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Добавляем схему UnitUpdate..."

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

class UnitUpdate(BaseModel):
    name: str | None = Field(None, max_length=50)
    short_name: str | None = Field(None, max_length=10)
EOF

echo "📝 Добавляем PUT-эндпоинт в units.py..."

cat > app/api/v1/endpoints/units.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.unit import Unit
from app.schemas.unit import UnitCreate, UnitRead, UnitUpdate

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

@router.put("/{unit_id}", response_model=UnitRead)
async def update_unit(unit_id: int, unit_in: UnitUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Unit).where(Unit.id == unit_id))
    db_unit = result.scalar_one_or_none()
    if not db_unit:
        raise HTTPException(status_code=404, detail="Единица не найдена")
    
    update_data = unit_in.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_unit, field, value)
    
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такая единица уже существует")
    
    await db.refresh(db_unit)
    return db_unit

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

echo "📝 Обновляем шаблон units/list.html (добавляем ID для модалки)..."

python3 - << 'PYEOF'
with open('app/templates/units/list.html', 'r') as f:
    content = f.read()

# Добавляем id к заголовку модалки и кнопке отправки, чтобы менять их текст
old_modal = '''        <div class="modal-header">
          <h5 class="modal-title">Новая единица измерения</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>'''

new_modal = '''        <div class="modal-header">
          <h5 class="modal-title" id="unit-modal-title">Новая единица измерения</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>'''

content = content.replace(old_modal, new_modal)

# Добавляем скрытое поле для ID (чтобы понимать, редактируем или создаем)
old_form_start = '<form id="create-form">'
new_form_start = '<form id="create-form"><input type="hidden" id="unit-id" value="">'
content = content.replace(old_form_start, new_form_start)

with open('app/templates/units/list.html', 'w') as f:
    f.write(content)
print("✅ Шаблон units обновлен (id для модалки).")
PYEOF

echo "📝 Обновляем JS для единиц (редактирование)..."

cat > app/static/js/units_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#units-table tbody');
  const createForm = document.getElementById('create-form');
  const modalTitle = document.getElementById('unit-modal-title');
  const unitIdInput = document.getElementById('unit-id');

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
          <button class="btn btn-sm btn-outline-primary py-0 px-1" onclick="editUnit(${u.id})" title="Редактировать"><i class="bi bi-pencil"></i></button>
          <button class="btn btn-sm btn-outline-danger py-0 px-1" onclick="deleteUnit(${u.id}, '${escapeHtml(u.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  // Открытие модалки для создания
  window.openCreateModal = () => {
    unitIdInput.value = '';
    modalTitle.textContent = 'Новая единица измерения';
    createForm.reset();
  };

  // Редактирование
  window.editUnit = async (id) => {
    try {
      const unit = await API.get(`/api/v1/units`); // Получаем все, чтобы найти нужную
      const found = unit.find(u => u.id === id);
      if (!found) throw new Error('Единица не найдена');
      
      unitIdInput.value = id;
      modalTitle.textContent = 'Редактирование единицы';
      createForm.elements['name'].value = found.name;
      createForm.elements['short_name'].value = found.short_name;
      
      new bootstrap.Modal(document.getElementById('createModal')).show();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // Сохранение (создание или обновление)
  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const id = unitIdInput.value;
    const payload = FormHelper.serialize(createForm);

    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      if (id) {
        await API.put(`/api/v1/units/${id}`, payload);
        window.showToast('Единица обновлена', 'success');
      } else {
        await API.post('/api/v1/units/', payload);
        window.showToast('Единица создана', 'success');
      }
      
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      unitIdInput.value = '';
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

  // Привязка кнопки "Добавить" к режиму создания
  document.querySelector('button[data-bs-target="#createModal"]')?.addEventListener('click', openCreateModal);

  loadUnits();
})();
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка редактирования добавлена в единицы измерения."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add edit functionality for units"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем модель PpeSize (привязка к категории)..."

cat > app/models/ppe_size.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_category import PpeCategory

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("category_id", "size_value", "gender", name="uq_category_size_gender"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("ppe_categories.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True, comment="М, Ж или NULL (унисекс)")

    category: Mapped["PpeCategory"] = relationship(back_populates="sizes")
EOF

echo "🔧 Обновляем связи в PpeCategory..."

python3 - << 'PYEOF'
with open('app/models/ppe_category.py', 'r') as f:
    content = f.read()

if 'sizes: Mapped' not in content:
    content = content.replace(
        'items: Mapped[list["PpeItem"]] = relationship(back_populates="category")',
        'items: Mapped[list["PpeItem"]] = relationship(back_populates="category")\n    sizes: Mapped[list["PpeSize"]] = relationship(back_populates="category", cascade="all, delete-orphan")'
    )
    content = content.replace(
        'from app.models.ppe_item import PpeItem',
        'from app.models.ppe_item import PpeItem\n    from app.models.ppe_size import PpeSize'
    )
    with open('app/models/ppe_category.py', 'w') as f:
        f.write(content)
    print("✅ Связь sizes добавлена в PpeCategory.")
PYEOF

echo "🔧 Убираем связь sizes из PpeItem (если она там есть)..."

python3 - << 'PYEOF'
with open('app/models/ppe_item.py', 'r') as f:
    content = f.read()

# Удаляем строку со связью sizes
content = content.replace(
    '\n    sizes: Mapped[list["PpeSize"]] = relationship(\n        back_populates="ppe_item", cascade="all, delete-orphan"\n    )',
    ''
)
# Удаляем импорт PpeSize, если он остался
content = content.replace(
    '    from app.models.ppe_size import PpeSize\n',
    ''
)
with open('app/models/ppe_item.py', 'w') as f:
    f.write(content)
print("✅ Связь sizes удалена из PpeItem.")
PYEOF

echo "📝 Обновляем схемы..."

cat > app/schemas/ppe_size.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class PpeSizeBase(BaseModel):
    category_id: int
    size_value: str = Field(..., max_length=50)
    gender: str | None = Field(None, pattern="^[МЖ]$")

class PpeSizeCreate(PpeSizeBase):
    pass

class PpeSizeRead(PpeSizeBase):
    id: int
    model_config = ConfigDict(from_attributes=True)
EOF

echo "📝 Обновляем API размеров (по категориям)..."

cat > app/api/v1/endpoints/ppe_sizes.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.ppe_size import PpeSize
from app.models.ppe_category import PpeCategory
from app.schemas.ppe_size import PpeSizeCreate, PpeSizeRead

router = APIRouter(prefix="/ppe_sizes", tags=["Справочник: Размеры СИЗ"])

@router.post("/", response_model=PpeSizeRead, status_code=status.HTTP_201_CREATED)
async def create_size(size_in: PpeSizeCreate, db: AsyncSession = Depends(get_db)):
    cat_res = await db.execute(select(PpeCategory).where(PpeCategory.id == size_in.category_id))
    if not cat_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Категория не найдена")

    db_size = PpeSize(**size_in.model_dump())
    db.add(db_size)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такой размер уже существует для этой категории")
    
    await db.refresh(db_size)
    return db_size

@router.get("/", response_model=list[PpeSizeRead])
async def get_sizes(category_id: int | None = None, gender: str | None = None, db: AsyncSession = Depends(get_db)):
    query = select(PpeSize)
    if category_id is not None:
        query = query.where(PpeSize.category_id == category_id)
    if gender:
        query = query.where(PpeSize.gender == gender)
    result = await db.execute(query)
    return result.scalars().all()

@router.delete("/{size_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_size(size_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSize).where(PpeSize.id == size_id))
    db_size = result.scalar_one_or_none()
    if not db_size:
        raise HTTPException(status_code=404, detail="Размер не найден")
    await db.delete(db_size)
    await db.commit()
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "move sizes to categories"

echo "🔄 Применяем миграцию..."
docker compose exec -T api alembic upgrade head

echo "📝 Обновляем интерфейс управления размерами (теперь в категориях)..."

# 1. Убираем кнопку "Размеры" из списка СИЗ и модалку размеров
python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Удаляем кнопку "Размеры" из таблицы (в JS это делается, но мы просто уберем её из HTML, если она там есть как кнопка)
# На самом деле кнопка рендерится в JS. Мы перепишем JS ниже.

# Удаляем модалку размеров из list.html (если она там есть)
import re
content = re.sub(r'<!-- Модальное окно управления размерами -->.*?</div>\s*</div>\s*</div>', '', content, flags=re.DOTALL)

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
print("✅ Модалка размеров удалена из списка СИЗ.")
PYEOF

# 2. Переписываем ppe_items_list.js (убираем управление размерами)
cat > app/static/js/ppe_items_list.js << 'EOF'
(() => {
  const tbody = document.querySelector('#items-table tbody');
  const createForm = document.getElementById('create-form');
  const createCategorySelect = document.getElementById('create-category');

  async function loadItems() {
    try {
      const items = await API.get('/api/v1/ppe_items');
      renderTable(items);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  async function loadCategoriesForSelect() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      createCategorySelect.innerHTML = '<option value="">Выберите категорию...</option>' +
        categories.map(c => `<option value="${c.id}">${escapeHtml(c.name)}</option>`).join('');
    } catch (err) {
      createCategorySelect.innerHTML = '<option value="">Ошибка загрузки</option>';
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(items) {
    if (!items.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Наименований пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = items.map(i => `
      <tr data-item-id="${i.id}">
        <td><strong>${escapeHtml(i.name)}</strong></td>
        <td><span class="badge bg-secondary">${escapeHtml(i.category?.name ?? '—')}</span></td>
        <td class="text-end">
          <a class="btn btn-sm btn-outline-primary" href="/ppe-items/${i.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteItem(${i.id}, '${escapeHtml(i.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
        </td>
      </tr>
    `).join('');
  }

  createForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const payload = FormHelper.serialize(createForm);
    payload.category_id = Number(payload.category_id);
    
    const btn = createForm.querySelector('button[type="submit"]');
    btn.disabled = true;
    try {
      await API.post('/api/v1/ppe_items/', payload);
      window.showToast('Наименование создано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteItem = async (id, name) => {
    if (!confirm(`Удалить наименование "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_items/${id}`, { method: 'DELETE' });
      window.showToast('Наименование удалено', 'success');
      loadItems();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'item_updated') loadItems();
  });

  loadCategoriesForSelect();
  loadItems();
})();
EOF

echo "📝 Добавляем управление размерами в категории..."

# 3. Обновляем шаблон категорий (добавляем кнопку и модалку)
python3 - << 'PYEOF'
with open('app/templates/ppe_categories/list.html', 'r') as f:
    content = f.read()

# Добавляем модалку размеров в конец блока content
modal_html = '''
<!-- Модальное окно управления размерами категории -->
<div class="modal fade" id="sizesModal" tabindex="-1">
  <div class="modal-dialog">
    <div class="modal-content">
      <form id="size-form">
        <input type="hidden" name="category_id" id="size-category-id">
        <div class="modal-header">
          <h5 class="modal-title">Размеры для: <span id="size-category-name"></span></h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
            <div class="mb-3">
                <label class="form-label">Новый размер</label>
                <div class="row g-2">
                    <div class="col-4">
                        <select class="form-select" name="gender">
                            <option value="">Унисекс</option>
                            <option value="М">Мужской</option>
                            <option value="Ж">Женский</option>
                        </select>
                    </div>
                    <div class="col-5">
                        <input type="text" class="form-control" name="size_value" placeholder="Например, 42" required>
                    </div>
                    <div class="col-3">
                        <button class="btn btn-primary w-100" type="submit">Добавить</button>
                    </div>
                </div>
            </div>
            <ul class="list-group" id="sizes-list">
                <!-- Список размеров -->
            </ul>
        </div>
      </form>
    </div>
  </div>
</div>
'''
if 'sizesModal' not in content:
    content = content.replace('{% endblock %}', modal_html + '\n{% endblock %}')

with open('app/templates/ppe_categories/list.html', 'w') as f:
    f.write(content)
print("✅ Модалка размеров добавлена в категории.")
PYEOF

# 4. Обновляем JS для категорий (добавляем логику размеров)
python3 - << 'PYEOF'
with open('app/static/js/ppe_categories_list.js', 'r') as f:
    content = f.read()

# Добавляем в renderTable кнопку "Размеры"
old_actions = '''          <a class="btn btn-sm btn-outline-primary" href="/ppe-categories/${c.id}/edit">Ред.</a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteCategory(${c.id}, '${escapeHtml(c.name)}')">Удалить</button>'''
new_actions = '''          <button class="btn btn-sm btn-outline-secondary" onclick="openSizesModal(${c.id}, '${escapeHtml(c.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary" href="/ppe-categories/${c.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteCategory(${c.id}, '${escapeHtml(c.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>'''

if old_actions in content:
    content = content.replace(old_actions, new_actions)
    print("✅ Кнопка размеров добавлена в таблицу категорий.")

# Добавляем функции для работы с модалкой размеров в конец файла (перед последним })
# Находим последнюю закрывающую скобку (конец IIFE)
# Проще перезаписать файл целиком, так как мы уже делали это.

# Перезаписываем ppe_categories_list.js с новой логикой
new_js = '''(() => {
  const tbody = document.querySelector('#categories-table tbody');
  const createForm = document.getElementById('create-form');
  const sizesModalElement = document.getElementById('sizesModal');
  const sizeForm = document.getElementById('size-form');
  const sizesList = document.getElementById('sizes-list');
  const sizeCategoryName = document.getElementById('size-category-name');
  const sizeCategoryIdInput = document.getElementById('size-category-id');

  async function loadCategories() {
    try {
      const categories = await API.get('/api/v1/ppe_categories');
      renderTable(categories);
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-danger py-4">Ошибка: ${err.message}</td></tr>`;
    }
  }

  function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }

  function renderTable(categories) {
    if (!categories.length) {
      tbody.innerHTML = `<tr><td colspan="4" class="text-center text-muted py-4">Категорий пока нет</td></tr>`;
      return;
    }
    tbody.innerHTML = categories.map(c => `
      <tr data-category-id="${c.id}">
        <td><strong>${escapeHtml(c.name)}</strong></td>
        <td>${escapeHtml(c.description ?? '—')}</td>
        <td class="text-end">
          <button class="btn btn-sm btn-outline-secondary" onclick="openSizesModal(${c.id}, '${escapeHtml(c.name)}')" title="Размеры"><i class="bi bi-rulers"></i></button>
          <a class="btn btn-sm btn-outline-primary" href="/ppe-categories/${c.id}/edit" title="Редактировать"><i class="bi bi-pencil"></i></a>
          <button class="btn btn-sm btn-outline-danger" onclick="deleteCategory(${c.id}, '${escapeHtml(c.name)}')" title="Удалить"><i class="bi bi-trash"></i></button>
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
      await API.post('/api/v1/ppe_categories/', payload);
      window.showToast('Категория создана', 'success');
      bootstrap.Modal.getInstance(document.getElementById('createModal')).hide();
      createForm.reset();
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      btn.disabled = false;
    }
  });

  window.deleteCategory = async (id, name) => {
    if (!confirm(`Удалить категорию "${name}"?`)) return;
    try {
      await API.request(`/api/v1/ppe_categories/${id}`, { method: 'DELETE' });
      window.showToast('Категория удалена', 'success');
      loadCategories();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  // --- Управление размерами ---
  window.openSizesModal = async (categoryId, categoryName) => {
    sizeCategoryIdInput.value = categoryId;
    sizeCategoryName.textContent = categoryName;
    sizesList.innerHTML = '<li class="list-group-item text-muted">Загрузка...</li>';
    
    const modal = new bootstrap.Modal(sizesModalElement);
    modal.show();

    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      sizesList.innerHTML = `<li class="list-group-item text-danger">Ошибка: ${err.message}</li>`;
    }
  };

  function renderSizesList(sizes) {
    if (!sizes.length) {
      sizesList.innerHTML = '<li class="list-group-item text-muted">Нет добавленных размеров</li>';
      return;
    }
    sizesList.innerHTML = sizes.map(s => {
      const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
      return `
      <li class="list-group-item d-flex justify-content-between align-items-center">
        ${escapeHtml(s.size_value)}${genderLabel}
        <button type="button" class="btn btn-sm btn-outline-danger" onclick="deleteSize(${s.id})">✕</button>
      </li>
    `}).join('');
  }

  sizeForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const categoryId = Number(sizeCategoryIdInput.value);
    const sizeValue = sizeForm.elements['size_value'].value.trim();
    const gender = sizeForm.elements['gender'].value || null;
    if (!sizeValue) return;

    try {
      await API.post('/api/v1/ppe_sizes/', { category_id: categoryId, size_value: sizeValue, gender: gender });
      window.showToast('Размер добавлен', 'success');
      sizeForm.reset();
      
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  });

  window.deleteSize = async (sizeId) => {
    if (!confirm('Удалить этот размер?')) return;
    try {
      await API.request(`/api/v1/ppe_sizes/${sizeId}`, { method: 'DELETE' });
      window.showToast('Размер удален', 'success');
      const categoryId = Number(sizeCategoryIdInput.value);
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      renderSizesList(sizes);
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    }
  };

  WS.subscribe((data) => {
    if (data.event === 'category_updated') loadCategories();
  });

  loadCategories();
})();
'''
with open('app/static/js/ppe_categories_list.js', 'w') as f:
    f.write(new_js)
print("✅ JS категорий обновлен (с размерами).")
PYEOF

# 5. Обновляем employee_edit.js (размеры теперь по категориям)
python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Заменяем getSizesForItem на getSizesForCategory
# Нам нужно знать category_id для выбранного СИЗ. 
# allPpeItems теперь должен содержать category_id.
# Мы уже загружаем allPpeItems, в них есть category_id (из API /ppe_items/).
# Заменим блок в createSizeRow и в itemSelect.addEventListener.

# 1. Меняем функцию getSizesForItem на getSizesForCategory
old_get_sizes = '''  async function getSizesForItem(itemId) {
    if (allSizesCache[itemId]) return allSizesCache[itemId];
    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?ppe_item_id=${itemId}`);
      allSizesCache[itemId] = sizes;
      return sizes;
    } catch (err) {
      return [];
    }
  }'''

new_get_sizes = '''  async function getSizesForCategory(categoryId) {
    if (allSizesCache[categoryId]) return allSizesCache[categoryId];
    try {
      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);
      allSizesCache[categoryId] = sizes;
      return sizes;
    } catch (err) {
      return [];
    }
  }'''

content = content.replace(old_get_sizes, new_get_sizes)

# 2. В createSizeRow используем category_id вместо itemId
old_block = '''    let sizeOptions = '';
    if (itemId) {
      const sizes = await getSizesForItem(itemId);
      let filteredSizes = sizes;
      if (currentGender) {
        filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
      }
      if (filteredSizes.length > 0) {
        sizeOptions = filteredSizes.map(s => {
          const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
          return `<option value="${s.size_value}" ${s.size_value === sizeValue ? 'selected' : ''}>${s.size_value}${genderLabel}</option>`;
        }).join('');
      }
    }'''

new_block = '''    let sizeOptions = '';
    if (itemId) {
      // Находим category_id для выбранного СИЗ
      const selectedItem = allPpeItems.find(i => i.id === itemId);
      if (selectedItem && selectedItem.category_id) {
        const sizes = await getSizesForCategory(selectedItem.category_id);
        let filteredSizes = sizes;
        if (currentGender) {
          filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
        }
        if (filteredSizes.length > 0) {
          sizeOptions = filteredSizes.map(s => {
            const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
            return `<option value="${s.size_value}" ${s.size_value === sizeValue ? 'selected' : ''}>${s.size_value}${genderLabel}</option>`;
          }).join('');
        }
      }
    }'''

content = content.replace(old_block, new_block)

# 3. В обработчике itemSelect тоже используем категорию
old_item_change = '''      const newItemId = Number(itemSelect.value);
      if (newItemId) {
        const sizes = await getSizesForItem(newItemId);
        const currentGender = form.elements['gender'].value || null;
        let filteredSizes = sizes;
        if (currentGender) filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
        
        const sizeCell = tr.children[1];
        if (filteredSizes.length > 0) {
          const opts = '<option value="">Выберите размер...</option>' + filteredSizes.map(s => {
            const g = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
            return `<option value="${s.size_value}">${s.size_value}${g}</option>`;
          }).join('');
          sizeCell.innerHTML = `<select class="form-select form-select-sm size-value-input" required>${opts}</select>`;
        } else {
          sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
        }
      }'''

new_item_change = '''      const newItemId = Number(itemSelect.value);
      if (newItemId) {
        const selectedItem = allPpeItems.find(i => i.id === newItemId);
        const sizeCell = tr.children[1];
        
        if (selectedItem && selectedItem.category_id) {
          const sizes = await getSizesForCategory(selectedItem.category_id);
          const currentGender = form.elements['gender'].value || null;
          let filteredSizes = sizes;
          if (currentGender) filteredSizes = sizes.filter(s => !s.gender || s.gender === currentGender);
          
          if (filteredSizes.length > 0) {
            const opts = '<option value="">Размер...</option>' + filteredSizes.map(s => {
              const g = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
              return `<option value="${s.size_value}">${s.size_value}${g}</option>`;
            }).join('');
            sizeCell.innerHTML = `<select class="form-select form-select-sm size-value-input" required>${opts}</select>`;
          } else {
            sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
          }
        } else {
           sizeCell.innerHTML = `<input type="text" class="form-control form-control-sm size-value-input" placeholder="Размер" required maxlength="50">`;
        }
      }'''

content = content.replace(old_item_change, new_item_change)

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
print("✅ employee_edit.js обновлен (размеры по категориям).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Размеры теперь привязаны к категориям."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "refactor: move sizes from ppe_items to ppe_categories"
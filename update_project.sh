#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Убираем функции и группы из datalist (чтобы не было пустых скобок)..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# Убираем функцию и группу из datalist
content = content.replace(
    '''      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name} (${i.function?.name ?? ''} / ${i.size_group?.name ?? ''})" data-id="${i.id}"></option>`
      ).join('');''',
    '''      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name}" data-id="${i.id}"></option>`
      ).join('');'''
)

# В editNorm тоже убираем скобки
content = content.replace(
    '''        itemSelect.value = `${item.name} (${item.function?.name ?? ''} / ${item.size_group?.name ?? ''})`;''',
    '''        itemSelect.value = item.name;'''
)

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
print("✅ datalist обновлен (без скобок).")
PYEOF

echo "📝 Добавляем защиту от удаления СИЗ, используемого в нормах или выдачах..."

cat > app/api/v1/endpoints/ppe_items.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, exists
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.ppe_item import PpeItem
from app.models.ppe_function import PpeFunction
from app.models.ppe_size_group import PpeSizeGroup
from app.models.unit import Unit
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.schemas.ppe_item import PpeItemCreate, PpeItemRead, PpeItemUpdate

router = APIRouter(prefix="/ppe_items", tags=["Справочник: Наименования СИЗ"])

def item_options():
    return [
        selectinload(PpeItem.function),
        selectinload(PpeItem.size_group),
        selectinload(PpeItem.unit)
    ]

@router.post("/", response_model=PpeItemRead, status_code=status.HTTP_201_CREATED)
async def create_item(item_in: PpeItemCreate, db: AsyncSession = Depends(get_db)):
    db_item = PpeItem(**item_in.model_dump())
    db.add(db_item)
    await db.commit()
    await db.refresh(db_item)
    
    result = await db.execute(select(PpeItem).where(PpeItem.id == db_item.id).options(*item_options()))
    return result.scalar_one()

@router.get("/", response_model=list[PpeItemRead])
async def get_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).options(*item_options()))
    return result.scalars().all()

@router.get("/{item_id}", response_model=PpeItemRead)
async def get_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id).options(*item_options()))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")
    return item

@router.put("/{item_id}", response_model=PpeItemRead)
async def update_item(item_id: int, item_in: PpeItemUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    if db_item.version != item_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")

    update_data = item_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_item, field, value)
    db_item.version += 1
    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "item_updated", "item_id": item_id})
    except Exception:
        pass

    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id).options(*item_options()))
    return result.scalar_one()

@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    # Проверяем, есть ли нормы на это СИЗ
    norm_exists = await db.execute(
        select(exists().where(PositionPpeNorm.ppe_item_id == item_id))
    )
    if norm_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Нельзя удалить СИЗ, так как оно используется в нормах выдачи"
        )

    # Проверяем, есть ли выдачи этого СИЗ
    issue_exists = await db.execute(
        select(exists().where(EmployeePpeIssue.ppe_item_id == item_id))
    )
    if issue_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Нельзя удалить СИЗ, так как оно было выдано сотрудникам"
        )

    try:
        await db.delete(db_item)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! СИЗ больше нельзя удалить, если оно используется."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: prevent deletion of ppe_items used in norms/issues; simplify datalist"
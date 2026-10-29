#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Перезаписываем position_ppe_norms.py (гарантированная подгрузка unit)..."

cat > app/api/v1/endpoints/position_ppe_norms.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.exc import IntegrityError
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.position import Position
from app.models.ppe_item import PpeItem
from app.models.unit import Unit
from app.schemas.position_ppe_norm import PositionPpeNormCreate, PositionPpeNormRead, PositionPpeNormUpdate

router = APIRouter(prefix="/position_ppe_norms", tags=["Нормы выдачи СИЗ"])


def norm_options():
    """Возвращает список опций для загрузки всех вложенных связей."""
    return [
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.category),
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.unit),
        selectinload(PositionPpeNorm.position).selectinload(Position.department)
    ]


async def get_norm_with_relations(db: AsyncSession, norm_id: int) -> PositionPpeNorm:
    """Загружает норму со всеми связями."""
    result = await db.execute(
        select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id).options(*norm_options())
    )
    return result.scalar_one()


@router.post("/", response_model=PositionPpeNormRead, status_code=status.HTTP_201_CREATED)
async def create_norm(norm_in: PositionPpeNormCreate, db: AsyncSession = Depends(get_db)):
    pos_res = await db.execute(select(Position).where(Position.id == norm_in.position_id))
    if not pos_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Должность не найдена")
        
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == norm_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    db_norm = PositionPpeNorm(**norm_in.model_dump())
    db.add(db_norm)
    
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400, 
            detail="Для этой должности норма на данное СИЗ уже существует."
        )
        
    return await get_norm_with_relations(db, db_norm.id)


@router.get("/", response_model=list[PositionPpeNormRead])
async def get_norms(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).options(*norm_options()))
    return result.scalars().all()


@router.get("/{norm_id}", response_model=PositionPpeNormRead)
async def get_norm(norm_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id).options(*norm_options()))
    norm = result.scalar_one_or_none()
    if not norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    return norm


@router.put("/{norm_id}", response_model=PositionPpeNormRead)
async def update_norm(norm_id: int, norm_in: PositionPpeNormUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    if db_norm.version != norm_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = norm_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_norm, field, value)
    db_norm.version += 1
    
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такая норма уже существует")
    
    try:
        await manager.broadcast_to_employee(0, {"event": "norm_updated", "id": norm_id})
    except: pass

    return await get_norm_with_relations(db, norm_id)


@router.delete("/{norm_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_norm(norm_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    try:
        await db.delete(db_norm)
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

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force eager loading of unit in norms"
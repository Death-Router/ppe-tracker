#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем схемы для PpeFunction и PpeSizeGroup..."

cat > app/schemas/ppe_function.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class PpeFunctionBase(BaseModel):
    name: str = Field(..., max_length=100)

class PpeFunctionCreate(PpeFunctionBase):
    pass

class PpeFunctionRead(PpeFunctionBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class PpeFunctionUpdate(PpeFunctionBase):
    name: str | None = None
    version: int
EOF

cat > app/schemas/ppe_size_group.py << 'EOF'
from pydantic import BaseModel, ConfigDict, Field

class PpeSizeGroupBase(BaseModel):
    name: str = Field(..., max_length=100)

class PpeSizeGroupCreate(PpeSizeGroupBase):
    pass

class PpeSizeGroupRead(PpeSizeGroupBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class PpeSizeGroupUpdate(PpeSizeGroupBase):
    name: str | None = None
    version: int
EOF

echo "📝 Создаем API для PpeFunction..."

cat > app/api/v1/endpoints/ppe_functions.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from app.db.session import get_db
from app.models.ppe_function import PpeFunction
from app.schemas.ppe_function import PpeFunctionCreate, PpeFunctionRead, PpeFunctionUpdate

router = APIRouter(prefix="/ppe_functions", tags=["Справочник: Функции СИЗ"])

@router.post("/", response_model=PpeFunctionRead, status_code=status.HTTP_201_CREATED)
async def create_function(func_in: PpeFunctionCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.name == func_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая функция уже существует")
    db_func = PpeFunction(**func_in.model_dump())
    db.add(db_func)
    await db.commit()
    await db.refresh(db_func)
    return db_func

@router.get("/", response_model=list[PpeFunctionRead])
async def get_functions(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).order_by(PpeFunction.name))
    return result.scalars().all()

@router.put("/{func_id}", response_model=PpeFunctionRead)
async def update_function(func_id: int, func_in: PpeFunctionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.id == func_id))
    db_func = result.scalar_one_or_none()
    if not db_func:
        raise HTTPException(status_code=404, detail="Функция не найдена")
    if db_func.version != func_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = func_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_func, field, value)
    db_func.version += 1
    await db.commit()
    await db.refresh(db_func)
    return db_func

@router.delete("/{func_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_function(func_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeFunction).where(PpeFunction.id == func_id))
    db_func = result.scalar_one_or_none()
    if not db_func:
        raise HTTPException(status_code=404, detail="Функция не найдена")
    try:
        await db.delete(db_func)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить функцию, есть привязанные СИЗ")
EOF

echo "📝 Создаем API для PpeSizeGroup..."

cat > app/api/v1/endpoints/ppe_size_groups.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.ppe_size_group import PpeSizeGroup
from app.schemas.ppe_size_group import PpeSizeGroupCreate, PpeSizeGroupRead, PpeSizeGroupUpdate

router = APIRouter(prefix="/ppe_size_groups", tags=["Справочник: Размерные группы"])

@router.post("/", response_model=PpeSizeGroupRead, status_code=status.HTTP_201_CREATED)
async def create_group(group_in: PpeSizeGroupCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.name == group_in.name))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Такая группа уже существует")
    db_group = PpeSizeGroup(**group_in.model_dump())
    db.add(db_group)
    await db.commit()
    await db.refresh(db_group)
    return db_group

@router.get("/", response_model=list[PpeSizeGroupRead])
async def get_groups(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).order_by(PpeSizeGroup.name))
    return result.scalars().all()

@router.put("/{group_id}", response_model=PpeSizeGroupRead)
async def update_group(group_id: int, group_in: PpeSizeGroupUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == group_id))
    db_group = result.scalar_one_or_none()
    if not db_group:
        raise HTTPException(status_code=404, detail="Группа не найдена")
    if db_group.version != group_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = group_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_group, field, value)
    db_group.version += 1
    await db.commit()
    await db.refresh(db_group)
    return db_group

@router.delete("/{group_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_group(group_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.id == group_id))
    db_group = result.scalar_one_or_none()
    if not db_group:
        raise HTTPException(status_code=404, detail="Группа не найдена")
    try:
        await db.delete(db_group)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить группу, есть привязанные СИЗ или размеры")
EOF

echo "🔧 Подключаем новые роутеры в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'ppe_functions' not in content.split('app.include_router')[0]:
    # Добавляем импорты
    content = content.replace(
        'from app.api.v1.endpoints import (',
        'from app.api.v1.endpoints import ppe_functions, ppe_size_groups, '
    )
    # Добавляем include_router
    content = content.replace(
        'app.include_router(units.router, prefix="/api/v1")',
        'app.include_router(units.router, prefix="/api/v1")\napp.include_router(ppe_functions.router, prefix="/api/v1")\napp.include_router(ppe_size_groups.router, prefix="/api/v1")'
    )
    print("✅ Новые роутеры подключены.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! API для функций и размерных групп создано."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add API and schemas for ppe_functions and ppe_size_groups"
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api import pagination
from app.api.db import commit_or_400
from app.core.deps import get_current_active_user
from app.core.security import get_password_hash
from app.db.session import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserRead, UserUpdate
from app.utils.broadcast import broadcast

router = APIRouter(prefix="/users", tags=["Пользователи"])

# Проверка, что текущий пользователь — админ
async def require_admin(current_user: User = Depends(get_current_active_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Доступ только для администратора")
    return current_user

@router.get("/", response_model=None)
async def get_users(
    params: pagination.PageDep,
    db: AsyncSession = Depends(get_db),
    _=Depends(require_admin),
    paginated: bool = Query(False, description="Вернуть страницу с метаданными"),
):
    """Пользователи. Без paginated — полный список (нужен для редактирования)."""
    base = select(User).order_by(User.username)

    if not paginated:
        result = await db.execute(base)
        return result.scalars().all()

    total = (
        await db.execute(select(func.count()).select_from(User))
    ).scalar_one()
    result = await db.execute(pagination.apply(base, params))
    items = result.scalars().all()

    return pagination.page_of([UserRead.model_validate(item) for item in items], total, params)

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
    await commit_or_400(db, "Ошибка при создании пользователя")
    
    await db.refresh(db_user)
    await broadcast(0, {"event": "user_updated", "id": db_user.id})
    return db_user

@router.put("/{user_id}", response_model=UserRead)
async def update_user(user_id: int, user_in: UserUpdate, db: AsyncSession = Depends(get_db), _ = Depends(require_admin)):
    result = await db.execute(select(User).where(User.id == user_id))
    db_user = result.scalar_one_or_none()
    if not db_user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    
    update_data = user_in.model_dump(exclude_unset=True)
    if update_data.get('password'):
        db_user.hashed_password = get_password_hash(update_data['password'])
        del update_data['password']
    
    for field, value in update_data.items():
        setattr(db_user, field, value)
    
    await db.commit()
    await db.refresh(db_user)
    await broadcast(0, {"event": "user_updated", "id": user_id})
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

    await broadcast(0, {"event": "user_updated", "id": user_id})

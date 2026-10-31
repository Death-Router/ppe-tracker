from fastapi import APIRouter, Depends, HTTPException, Response, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.user import User
from app.core.csrf import require_csrf
from app.core.security import verify_password

router = APIRouter(prefix="/auth", tags=["Аутентификация"])

class LoginRequest(BaseModel):
    username: str
    password: str

# Вход не проверяет CSRF: до первого входа токена в сессии ещё нет.
# Сам по себе «login CSRF» безвреден — он лишь залогинил бы жертву чужим аккаунтом.
@router.post("/login")
async def login(request: Request, login_data: LoginRequest, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.username == login_data.username))
    user = result.scalar_one_or_none()
    
    if not user or not verify_password(login_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Неверное имя пользователя или пароль")
    
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Пользователь заблокирован")
    
    # Сохраняем ID пользователя в сессии (cookie)
    request.session["user_id"] = user.id
    
    return {"message": "Успешный вход", "role": user.role}

@router.post("/logout")
async def logout(request: Request, _=Depends(require_csrf)):
    request.session.clear()
    return {"message": "Вы вышли"}

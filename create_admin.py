import asyncio
import os
from sqlalchemy import select

# Импортируем ВСЕ модели, чтобы SQLAlchemy видел связи
from app.models.user import User
from app.models.department import Department
from app.models.position import Position
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.ppe_size import PpeSize
from app.models.position_ppe_norm import PositionPpeNorm

from app.db.session import async_session_maker
from app.core.security import get_password_hash

async def create_admin():
    username = os.getenv("ADMIN_USERNAME", "admin")
    password = os.getenv("ADMIN_PASSWORD", "admin123")
    
    async with async_session_maker() as db:
        result = await db.execute(select(User).where(User.username == username))
        user = result.scalar_one_or_none()
        
        if user:
            print(f"Пользователь {username} уже существует.")
            return
        
        new_user = User(
            username=username,
            hashed_password=get_password_hash(password),
            role="admin",
            is_active=True
        )
        db.add(new_user)
        await db.commit()
        print(f"Администратор {username} создан!")

if __name__ == "__main__":
    asyncio.run(create_admin())

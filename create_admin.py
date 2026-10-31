import asyncio

from sqlalchemy import select

# Импортируем модели, чтобы SQLAlchemy знал обо всех связях между таблицами
from app.models.department import Department  # noqa: F401
from app.models.employee import Employee  # noqa: F401
from app.models.employee_ppe_issue import EmployeePpeIssue  # noqa: F401
from app.models.employee_ppe_size import EmployeePpeSize  # noqa: F401
from app.models.position import Position  # noqa: F401
from app.models.position_ppe_norm import PositionPpeNorm  # noqa: F401
from app.models.ppe_function import PpeFunction  # noqa: F401
from app.models.ppe_item import PpeItem  # noqa: F401
from app.models.ppe_size import PpeSize  # noqa: F401
from app.models.ppe_size_group import PpeSizeGroup  # noqa: F401
from app.models.unit import Unit  # noqa: F401
from app.models.user import User

from app.core.config import settings
from app.core.security import get_password_hash
from app.db.session import async_session_maker


async def create_admin():
    username = settings.ADMIN_USERNAME
    password = settings.ADMIN_PASSWORD

    # Пароль по умолчанию не создаём: иначе в открытом репозитории
    # появляется известный всем логин/пароль администратора.
    if not password:
        raise SystemExit(
            "ADMIN_PASSWORD не задан.\n"
            "Добавьте в .env строки:\n"
            "  ADMIN_USERNAME=admin\n"
            "  ADMIN_PASSWORD=<надёжный пароль>\n"
            "и запустите скрипт снова."
        )

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
            is_active=True,
        )
        db.add(new_user)
        await db.commit()
        print(f"Администратор {username} создан!")


if __name__ == "__main__":
    asyncio.run(create_admin())

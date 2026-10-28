from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings

# Создаем асинхронный движок
engine = create_async_engine(
    settings.database_url,
    echo=False,  # Поставьте True, если хотите видеть все SQL-запросы в консоли
    future=True,
)

# Фабрика сессий (Session-per-Request)
async_session_maker = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)


# Зависимость для FastAPI (будем использовать в эндпоинтах)
async def get_db():
    async with async_session_maker() as session:
        yield session

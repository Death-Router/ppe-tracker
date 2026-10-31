from passlib.context import CryptContext

from app.core.config import settings

# Ключ подписи сессий берётся из настроек (.env), а не из кода:
# значение в репозитории означало бы, что любой читатель может подделать сессию.
SECRET_KEY = settings.SECRET_KEY

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_password_hash(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

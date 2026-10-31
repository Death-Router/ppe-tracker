from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Значение-заглушка, с которым приложение работало раньше.
# Такое значение нельзя использовать: оно лежит в открытом репозитории.
INSECURE_DEFAULT_SECRET = "super-secret-key-change-in-production"  # noqa: S105 — маркер, а не секрет


class Settings(BaseSettings):
    # Окружение: development | production
    ENVIRONMENT: str = "development"

    # Настройки БД (будут браться из .env)
    POSTGRES_USER: str = "ppe_user"
    POSTGRES_PASSWORD: str = "ppe_password"  # noqa: S105 — дефолт для локальной разработки
    POSTGRES_DB: str = "ppe_db"
    POSTGRES_HOST: str = "db"
    POSTGRES_PORT: int = 5432

    # Ключ подписи сессионных cookie. Обязателен, см. .env.example
    SECRET_KEY: str = ""
    # Отправлять cookie только по HTTPS (включайте в продакшене)
    SESSION_COOKIE_SECURE: bool = False
    # Время жизни сессии в секундах (7 дней)
    SESSION_MAX_AGE: int = 60 * 60 * 24 * 7

    # Реквизиты администратора для create_admin.py
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = ""

    # Импорт из Excel: защита от «файла на 200 МБ» и от простыни на 100k строк
    MAX_IMPORT_FILE_MB: int = 10
    MAX_IMPORT_ROWS: int = 5000

    # Собираем URL для подключения
    @property
    def database_url(self) -> str:
        return f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"

    @model_validator(mode="after")
    def _check_secret_key(self):
        if not self.SECRET_KEY or self.SECRET_KEY == INSECURE_DEFAULT_SECRET:
            raise RuntimeError(
                "SECRET_KEY не задан или оставлен небезопасным по умолчанию.\n"
                "Сгенерируйте ключ и добавьте его в .env:\n"
                '  python -c "import secrets; print(secrets.token_urlsafe(48))"'
            )
        if len(self.SECRET_KEY) < 32:
            raise RuntimeError(
                "SECRET_KEY слишком короткий: нужно не менее 32 символов."
            )
        return self

    # Указываем Pydantic, откуда читать переменные
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )


# Создаем глобальный объект настроек
settings = Settings()

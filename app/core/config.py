from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Настройки БД (будут браться из .env)
    POSTGRES_USER: str = "ppe_user"
    POSTGRES_PASSWORD: str = "ppe_password"
    POSTGRES_DB: str = "ppe_db"
    POSTGRES_HOST: str = "db"
    POSTGRES_PORT: int = 5432

    # Собираем URL для подключения
    @property
    def database_url(self) -> str:
        return f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"

    # Указываем Pydantic, откуда читать переменные
    model_config = SettingsConfigDict(
        env_file=".env", env_file_encoding="utf-8", extra="ignore"
    )


# Создаем глобальный объект настроек
settings = Settings()

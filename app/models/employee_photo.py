"""Фото сотрудника: в БД только метаданные, сам файл — в каталоге PHOTO_DIR.

Почему так: фото — это персональные данные, и хранение файлов на томе
позволяет держать дамп базы лёгким (фото не едет в pg_dump, а переносится
каталогом). Путь в БД не хранится: каталог задаётся окружением, поэтому
базу и файлы можно переносить независимо.
"""
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee


class EmployeePhoto(Base):
    __tablename__ = "employee_photos"

    employee_id: Mapped[int] = mapped_column(
        ForeignKey("employees.id", ondelete="CASCADE"), primary_key=True
    )
    # Только имя файла внутри PHOTO_DIR, без каталогов
    filename: Mapped[str] = mapped_column(String(64), nullable=False)
    mime_type: Mapped[str] = mapped_column(String(50), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    # sha256 содержимого: ETag для кэша браузера и контроль подмены файла
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    employee: Mapped["Employee"] = relationship(back_populates="photo")

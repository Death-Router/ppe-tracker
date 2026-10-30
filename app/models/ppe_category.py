from typing import TYPE_CHECKING
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_size import PpeSize

class PpeCategory(Base):
    __tablename__ = "ppe_categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    # Связь с размерами (для сотрудников)
    sizes: Mapped[list["PpeSize"]] = relationship(back_populates="category", cascade="all, delete-orphan")

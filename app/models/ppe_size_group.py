from typing import TYPE_CHECKING

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_item import PpeItem
    from app.models.ppe_size import PpeSize

class PpeSizeGroup(Base):
    __tablename__ = "ppe_size_groups"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    # Пояснение для пользователя: что именно меряется в этой группе
    # (например, «Обхват груди» для костюмов или «Размер по ГОСТ» для обуви)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    items: Mapped[list["PpeItem"]] = relationship(back_populates="size_group")
    sizes: Mapped[list["PpeSize"]] = relationship(back_populates="size_group", cascade="all, delete-orphan")

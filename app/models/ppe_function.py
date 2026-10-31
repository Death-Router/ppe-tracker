from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_item import PpeItem

class PpeFunction(Base):
    __tablename__ = "ppe_functions"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    items: Mapped[list["PpeItem"]] = relationship(back_populates="function")

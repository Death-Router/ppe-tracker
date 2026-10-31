from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_size_group import PpeSizeGroup

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("size_group_id", "size_value", "gender", name="uq_size_group_size_gender"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    size_group_id: Mapped[int] = mapped_column(ForeignKey("ppe_size_groups.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True, comment="М, Ж или NULL (унисекс)")

    size_group: Mapped["PpeSizeGroup"] = relationship(back_populates="sizes")

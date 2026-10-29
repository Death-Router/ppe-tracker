from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_category import PpeCategory

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("category_id", "size_value", "gender", name="uq_category_size_gender"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    category_id: Mapped[int] = mapped_column(ForeignKey("ppe_categories.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True, comment="М, Ж или NULL (унисекс)")

    category: Mapped["PpeCategory"] = relationship(back_populates="sizes")

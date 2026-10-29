from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_item import PpeItem

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("ppe_item_id", "size_value", name="uq_ppe_item_size"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)

    ppe_item: Mapped["PpeItem"] = relationship(back_populates="sizes")

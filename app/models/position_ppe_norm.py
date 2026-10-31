from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.position import Position
    from app.models.ppe_item import PpeItem

class PositionPpeNorm(Base):
    __tablename__ = "position_ppe_norms"
    __table_args__ = (
        UniqueConstraint("position_id", "ppe_item_id", name="uq_position_ppe_item"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    position_id: Mapped[int] = mapped_column(ForeignKey("positions.id", ondelete="CASCADE"))
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    
    wear_period_value: Mapped[str] = mapped_column(String(50), comment="Например: 1, 12, 6")
    wear_period_unit: Mapped[str] = mapped_column(String(20), comment="год, месяц, до износа")
    quantity: Mapped[str] = mapped_column(String(50), default="1")

    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    position: Mapped["Position"] = relationship(back_populates="ppe_norms")
    ppe_item: Mapped["PpeItem"] = relationship(back_populates="position_norms")

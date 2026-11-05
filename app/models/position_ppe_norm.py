from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Index, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.position import Position
    from app.models.ppe_item import PpeItem
    from app.models.typical_norm import TypicalNorm

class PositionPpeNorm(Base):
    __tablename__ = "position_ppe_norms"
    # Пара «должность + СИЗ» не уникальна: у нормы есть основное наименование
    # и до четырёх альтернатив, ограничение снято миграцией a9f3c06b2d18.
    # UniqueConstraint здесь возвращать нельзя — автогенерация попытается
    # восстановить ограничение и упадёт на базе, где альтернативы уже есть.
    # Индекс повторяет тот, что создала эта же миграция.
    __table_args__ = (
        Index("ix_position_ppe_norms_position_item", "position_id", "ppe_item_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    position_id: Mapped[int] = mapped_column(ForeignKey("positions.id", ondelete="CASCADE"))
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    
    wear_period_value: Mapped[str] = mapped_column(String(50), comment="Например: 1, 12, 6")
    wear_period_unit: Mapped[str] = mapped_column(String(20), comment="год, месяц, до износа")
    quantity: Mapped[str] = mapped_column(String(50), default="1")

    # Пункт типовых отраслевых норм — графа «Пункт Норм» личной карточки.
    # RESTRICT: пункт, на который ссылаются нормы, удалять нельзя, иначе в
    # карточке молча пропадёт основание выдачи
    typical_norm_id: Mapped[int | None] = mapped_column(
        ForeignKey("typical_norms.id", ondelete="RESTRICT"), nullable=True
    )

    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    position: Mapped["Position"] = relationship(back_populates="ppe_norms")
    ppe_item: Mapped["PpeItem"] = relationship(back_populates="position_norms")
    typical_norm: Mapped["TypicalNorm | None"] = relationship(back_populates="norms")

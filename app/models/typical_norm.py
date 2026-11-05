from typing import TYPE_CHECKING

from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.position_ppe_norm import PositionPpeNorm

class TypicalNorm(Base):
    """Типовые отраслевые нормы: пункт нормы и его описание.

    Нужны для графы «Пункт Норм» личной карточки учёта СИЗ: в бумажной форме
    там пишут пункт приложения к Положению, по которому выдаётся СИЗ.
    Справочник отдельный, а не текстовое поле в норме, — один и тот же пункт
    повторяется у десятков должностей, а опечатка в номере потом не находится.
    """

    __tablename__ = "typical_norms"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    # Пункт нормы в том виде, как он написан в документе: «п. 4», «п. 12.1»
    clause: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    description: Mapped[str] = mapped_column(String(500))

    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    norms: Mapped[list["PositionPpeNorm"]] = relationship(back_populates="typical_norm")

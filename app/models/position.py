from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.department import Department
    from app.models.employee import Employee
    from app.models.position_ppe_norm import PositionPpeNorm

class Position(Base):
    __tablename__ = "positions"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), index=True)
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id", ondelete="CASCADE"))
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    department: Mapped["Department"] = relationship(back_populates="positions")
    employees: Mapped[list["Employee"]] = relationship(back_populates="position_rel")
    ppe_norms: Mapped[list["PositionPpeNorm"]] = relationship(back_populates="position", cascade="all, delete-orphan")

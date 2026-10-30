from typing import TYPE_CHECKING
from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee_ppe_issue import EmployeePpeIssue
    from app.models.ppe_function import PpeFunction
    from app.models.ppe_size_group import PpeSizeGroup
    from app.models.position_ppe_norm import PositionPpeNorm

class PpeItem(Base):
    __tablename__ = "ppe_items"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    
    function_id: Mapped[int | None] = mapped_column(ForeignKey("ppe_functions.id", ondelete="SET NULL"), nullable=True)
    size_group_id: Mapped[int | None] = mapped_column(ForeignKey("ppe_size_groups.id", ondelete="SET NULL"), nullable=True)
    
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)
    unit_id: Mapped[int | None] = mapped_column(ForeignKey("units.id"), nullable=True)

    function: Mapped["PpeFunction | None"] = relationship(back_populates="items")
    size_group: Mapped["PpeSizeGroup | None"] = relationship(back_populates="items")
    unit: Mapped["Unit | None"] = relationship()
    
    employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")
    position_norms: Mapped[list["PositionPpeNorm"]] = relationship(back_populates="ppe_item", cascade="all, delete-orphan")

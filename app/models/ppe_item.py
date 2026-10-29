from typing import TYPE_CHECKING
from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee_ppe_size import EmployeePpeSize
    from app.models.employee_ppe_issue import EmployeePpeIssue
    from app.models.ppe_category import PpeCategory
    from app.models.position_ppe_norm import PositionPpeNorm


class PpeItem(Base):
    __tablename__ = "ppe_items"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(150), index=True)
    category_id: Mapped[int] = mapped_column(
        ForeignKey("ppe_categories.id", ondelete="RESTRICT")
    )
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    category: Mapped["PpeCategory"] = relationship(back_populates="items")
    
    employee_sizes: Mapped[list["EmployeePpeSize"]] = relationship(
        back_populates="ppe_item"
    )
    employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(
        back_populates="ppe_item", cascade="all, delete-orphan"
    )
    position_norms: Mapped[list["PositionPpeNorm"]] = relationship(
        back_populates="ppe_item", cascade="all, delete-orphan"
    )

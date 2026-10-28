from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.ppe_item import PpeItem


class EmployeePpeSize(Base):
    __tablename__ = "employee_ppe_sizes"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)

    employee_id: Mapped[int] = mapped_column(
        ForeignKey("employees.id", ondelete="CASCADE")
    )
    ppe_item_id: Mapped[int] = mapped_column(
        ForeignKey("ppe_items.id", ondelete="RESTRICT")
    )

    size_value: Mapped[str] = mapped_column(String(50))

    employee: Mapped["Employee"] = relationship(back_populates="ppe_sizes")
    ppe_item: Mapped["PpeItem"] = relationship(back_populates="employee_sizes")

    __table_args__ = (
        UniqueConstraint("employee_id", "ppe_item_id", name="uq_employee_ppe_item"),
    )

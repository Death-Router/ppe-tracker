from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.ppe_size_group import PpeSizeGroup

class EmployeePpeSize(Base):
    __tablename__ = "employee_ppe_sizes"
    __table_args__ = (
        UniqueConstraint("employee_id", "size_group_id", name="uq_employee_size_group"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id", ondelete="CASCADE"))
    size_group_id: Mapped[int] = mapped_column(ForeignKey("ppe_size_groups.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)

    employee: Mapped["Employee"] = relationship(back_populates="ppe_sizes")
    size_group: Mapped["PpeSizeGroup"] = relationship()

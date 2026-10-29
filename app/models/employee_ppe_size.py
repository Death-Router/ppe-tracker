from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.ppe_category import PpeCategory

class EmployeePpeSize(Base):
    __tablename__ = "employee_ppe_sizes"
    __table_args__ = (
        UniqueConstraint("employee_id", "category_id", name="uq_employee_category_size"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id", ondelete="CASCADE"))
    category_id: Mapped[int] = mapped_column(ForeignKey("ppe_categories.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)

    employee: Mapped["Employee"] = relationship(back_populates="ppe_sizes")
    category: Mapped["PpeCategory"] = relationship()

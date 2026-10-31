from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.ppe_item import PpeItem

class EmployeePpeIssue(Base):
    __tablename__ = "employee_ppe_issues"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    
    employee_id: Mapped[int] = mapped_column(ForeignKey("employees.id", ondelete="CASCADE"))
    ppe_item_id: Mapped[int] = mapped_column(ForeignKey("ppe_items.id", ondelete="CASCADE"))
    
    issue_date: Mapped[date] = mapped_column(Date, nullable=False)
    quantity: Mapped[str] = mapped_column(String(50), default="1")
    size_value: Mapped[str | None] = mapped_column(String(50), nullable=True)
    
    # Дата окончания срока носки (рассчитывается автоматически)
    expiry_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    employee: Mapped["Employee"] = relationship(back_populates="ppe_issues")
    ppe_item: Mapped["PpeItem"] = relationship(back_populates="employee_issues")

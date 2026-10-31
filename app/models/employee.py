from datetime import date
from typing import TYPE_CHECKING

from sqlalchemy import Date, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.department import Department
    from app.models.employee_ppe_issue import EmployeePpeIssue
    from app.models.employee_ppe_size import EmployeePpeSize
    from app.models.position import Position

class Employee(Base):
    __tablename__ = "employees"
    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    personnel_number: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    last_name: Mapped[str] = mapped_column(String(100))
    first_name: Mapped[str] = mapped_column(String(100))
    middle_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    
    department_id: Mapped[int] = mapped_column(ForeignKey("departments.id"), nullable=True) 
    position_id: Mapped[int] = mapped_column(ForeignKey("positions.id"), nullable=True)

    hire_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    position_change_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True)
    height: Mapped[str | None] = mapped_column(String(10), nullable=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    ppe_sizes: Mapped[list["EmployeePpeSize"]] = relationship(back_populates="employee", cascade="all, delete-orphan")
    ppe_issues: Mapped[list["EmployeePpeIssue"]] = relationship(back_populates="employee", cascade="all, delete-orphan")
    department_rel: Mapped["Department"] = relationship(back_populates="employees")
    position_rel: Mapped["Position"] = relationship(back_populates="employees")

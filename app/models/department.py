from typing import TYPE_CHECKING, Optional

from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.employee import Employee
    from app.models.position import Position

class Department(Base):
    __tablename__ = "departments"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    
    # Ссылка на самого себя (вышестоящее подразделение)
    parent_id: Mapped[int | None] = mapped_column(ForeignKey("departments.id", ondelete="SET NULL"), nullable=True)
    
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    # Связи
    parent: Mapped[Optional["Department"]] = relationship(remote_side=[id], back_populates="children")
    # Без delete-orphan: удаление подразделения не должно молча уносить поддерево
    children: Mapped[list["Department"]] = relationship(back_populates="parent")
    
    positions: Mapped[list["Position"]] = relationship(back_populates="department")
    employees: Mapped[list["Employee"]] = relationship(back_populates="department_rel")

from typing import TYPE_CHECKING
from sqlalchemy import String, Boolean, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.department import Department

class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(20), default="safety_officer")  # admin или safety_officer
    
    # Для safety_officer: к какому подразделению привязан
    department_id: Mapped[int | None] = mapped_column(ForeignKey("departments.id"), nullable=True)
    # Видеть ли дочерние подразделения (если иерархия)
    include_subdepartments: Mapped[bool] = mapped_column(Boolean, default=False)
    
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    department: Mapped["Department | None"] = relationship()

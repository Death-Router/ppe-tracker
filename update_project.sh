#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем устаревшую связь employee_sizes из PpeItem..."

cat > app/models/ppe_item.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
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
    
    employee_issues: Mapped[list["EmployeePpeIssue"]] = relationship(
        back_populates="ppe_item", cascade="all, delete-orphan"
    )
    position_norms: Mapped[list["PositionPpeNorm"]] = relationship(
        back_populates="ppe_item", cascade="all, delete-orphan"
    )
EOF

echo "🔧 Проверяем модель EmployeePpeSize (должна ссылаться на категорию)..."

cat > app/models/employee_ppe_size.py << 'EOF'
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
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Если в логах 'Application startup complete', значит, всё работает."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove obsolete employee_sizes relationship from PpeItem"
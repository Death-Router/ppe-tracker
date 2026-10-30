#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем связь sizes из PpeCategory и обновляем PpeSize..."

# 1. Убираем связь sizes из PpeCategory
cat > app/models/ppe_category.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base

if TYPE_CHECKING:
    pass

class PpeCategory(Base):
    __tablename__ = "ppe_categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)
EOF

# 2. Обновляем PpeSize (убираем связь с PpeCategory, оставляем size_group)
cat > app/models/ppe_size.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import String, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_size_group import PpeSizeGroup

class PpeSize(Base):
    __tablename__ = "ppe_sizes"
    __table_args__ = (
        UniqueConstraint("size_group_id", "size_value", "gender", name="uq_size_group_size_gender"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    size_group_id: Mapped[int] = mapped_column(ForeignKey("ppe_size_groups.id", ondelete="CASCADE"))
    size_value: Mapped[str] = mapped_column(String(50), nullable=False)
    gender: Mapped[str | None] = mapped_column(String(1), nullable=True, comment="М, Ж или NULL (унисекс)")

    size_group: Mapped["PpeSizeGroup"] = relationship(back_populates="sizes")
EOF

# 3. Обновляем EmployeePpeSize (меняем category_id на size_group_id)
cat > app/models/employee_ppe_size.py << 'EOF'
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
EOF

echo "🔧 Обновляем Employee (связь ppe_sizes теперь через size_group)..."

# В Employee связь ppe_sizes уже есть, но она ссылается на EmployeePpeSize, который мы обновили.
# Ничего менять не нужно, если связь настроена через back_populates.

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Связи обновлены, ошибка должна исчезнуть."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove obsolete sizes relationship from PpeCategory and update EmployeePpeSize to size_group"
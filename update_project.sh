#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем связь items из PpeCategory (так как PpeItem больше не ссылается на категорию)..."

cat > app/models/ppe_category.py << 'EOF'
from typing import TYPE_CHECKING
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ppe_size import PpeSize

class PpeCategory(Base):
    __tablename__ = "ppe_categories"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, index=True)
    description: Mapped[str | None] = mapped_column(String(500), nullable=True)
    version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)

    # Связь с размерами (для сотрудников)
    sizes: Mapped[list["PpeSize"]] = relationship(back_populates="category", cascade="all, delete-orphan")
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Ошибка с PpeCategory.items исправлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove obsolete items relationship from PpeCategory"
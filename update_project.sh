#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Увеличиваем размер поля name в PpeItem..."

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
    name: Mapped[str] = mapped_column(String(255), index=True)  # Увеличили до 255
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

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "increase ppe_item name length to 255"
docker compose exec -T api alembic upgrade head

echo "📝 Обновляем import_data.py (защита от длинных названий)..."

python3 - << 'PYEOF'
with open('app/api/v1/endpoints/import_data.py', 'r') as f:
    content = f.read()

# Добавляем обрезку названий до 255 символов
old_code = '''            if not name:
                errors.append(f"Строка {index + 2}: Пустое наименование")
                continue'''

new_code = '''            if not name:
                errors.append(f"Строка {index + 2}: Пустое наименование")
                continue
            
            # Обрезаем слишком длинные названия
            if len(name) > 255:
                name = name[:252] + "..."
                errors.append(f"Строка {index + 2}: Название обрезано до 255 символов")'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Защита от длинных названий добавлена.")
else:
    print("⚠️ Не удалось найти блок для добавления защиты.")

with open('app/api/v1/endpoints/import_data.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь можно импортировать длинные названия."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: increase ppe_item name length to 255 and truncate long names on import"
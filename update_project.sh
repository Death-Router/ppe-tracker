#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем модель Unit..."

cat > app/models/unit.py << 'EOF'
from sqlalchemy import String
from sqlalchemy.orm import Mapped, mapped_column
from app.db.base import Base

class Unit(Base):
    __tablename__ = "units"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)  # Например, "Пара"
    short_name: Mapped[str] = mapped_column(String(10), nullable=False)         # Например, "пар"
EOF

echo "🔧 Привязываем unit_id к PpeItem (и убираем из норм/выдач)..."

# Обновляем PpeItem
python3 - << 'PYEOF'
with open('app/models/ppe_item.py', 'r') as f:
    content = f.read()

if 'unit_id' not in content:
    # Добавляем поле unit_id
    content = content.replace(
        'version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)',
        'version: Mapped[int] = mapped_column(default=1, server_default="1", nullable=False)\n    unit_id: Mapped[int | None] = mapped_column(ForeignKey("units.id"), nullable=True)'
    )
    # Добавляем связь
    content = content.replace(
        'category: Mapped["PpeCategory"] = relationship(back_populates="items")',
        'category: Mapped["PpeCategory"] = relationship(back_populates="items")\n    unit: Mapped["Unit | None"] = relationship()'
    )
    # Добавляем импорт Unit
    content = content.replace(
        'from app.models.ppe_category import PpeCategory',
        'from app.models.ppe_category import PpeCategory\n    from app.models.unit import Unit'
    )
    with open('app/models/ppe_item.py', 'w') as f:
        f.write(content)
    print("✅ unit_id добавлен в PpeItem.")
else:
    print("ℹ️ unit_id уже есть в PpeItem.")
PYEOF

# Убираем unit_id из PositionPpeNorm (если был добавлен)
python3 - << 'PYEOF'
with open('app/models/position_ppe_norm.py', 'r') as f:
    content = f.read()

# Удаляем строку с unit_id
content = content.replace('\n    unit_id: Mapped[int | None] = mapped_column(ForeignKey("units.id"), nullable=True)', '')
# Удаляем связь unit
content = content.replace('\n    unit: Mapped["Unit | None"] = relationship()', '')

with open('app/models/position_ppe_norm.py', 'w') as f:
    f.write(content)
print("✅ unit_id удален из PositionPpeNorm (если был).")
PYEOF

# Убираем unit_id из EmployeePpeIssue (если был добавлен)
python3 - << 'PYEOF'
with open('app/models/employee_ppe_issue.py', 'r') as f:
    content = f.read()

# Удаляем строку с unit_id
content = content.replace('\n    unit_id: Mapped[int | None] = mapped_column(ForeignKey("units.id"), nullable=True)', '')
# Удаляем связь unit
content = content.replace('\n    unit: Mapped["Unit | None"] = relationship()', '')

with open('app/models/employee_ppe_issue.py', 'w') as f:
    f.write(content)
print("✅ unit_id удален из EmployeePpeIssue (если был).")
PYEOF

echo "🔧 Обновляем alembic/env.py для Alembic..."

python3 - << 'PYEOF'
with open('alembic/env.py', 'r') as f:
    content = f.read()

if 'from app.models.unit import Unit' not in content:
    content = content.replace(
        'from app.models.employee import Employee',
        'from app.models.employee import Employee\nfrom app.models.unit import Unit'
    )
    with open('alembic/env.py', 'w') as f:
        f.write(content)
    print("✅ Unit добавлен в alembic/env.py.")
else:
    print("ℹ️ Unit уже есть в alembic/env.py.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "add units table and unit_id to ppe_items"
docker compose exec -T api alembic upgrade head

echo "✅ ГОТОВО! Модель Unit создана и привязана к PpeItem."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add units model and unit_id to ppe_items"
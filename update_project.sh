#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем циклический импорт из app/db/base.py..."

# Оставляем только Base
cat > app/db/base.py << 'EOF'
from sqlalchemy.orm import DeclarativeBase

class Base(DeclarativeBase):
    pass
EOF

echo "🔧 Обновляем alembic/env.py (чтобы Alembic видел все модели)..."

python3 - << 'PYEOF'
with open('alembic/env.py', 'r') as f:
    content = f.read()

imports = """
from app.models.department import Department
from app.models.position import Position
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.employee_ppe_issue import EmployeePpeIssue
"""

# Добавляем импорты, если их еще нет (или обновляем)
if 'from app.models.employee_ppe_issue import EmployeePpeIssue' not in content:
    if 'target_metadata = ' in content:
        content = content.replace('target_metadata = ', imports + '\ntarget_metadata = ')
    else:
        content += imports

with open('alembic/env.py', 'w') as f:
    f.write(content)
print("✅ alembic/env.py обновлен.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Генерируем миграцию..."
docker compose exec -T api alembic revision --autogenerate -m "add employee_ppe_issues table (retry)"

echo "🔄 Применяем миграцию..."
docker compose exec -T api alembic upgrade head

echo "✅ ГОТОВО! Приложение должно подняться."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: resolve circular import for employee_ppe_issues"
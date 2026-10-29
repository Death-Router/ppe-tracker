#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🛠 Исправляем регистр категорий (с импортом всех моделей)..."

cat > fix_case.py << 'EOF'
import asyncio
from sqlalchemy import select

# Импортируем ВСЕ модели, чтобы SQLAlchemy видел связи
from app.models.user import User
from app.models.department import Department
from app.models.position import Position
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.ppe_size import PpeSize
from app.models.position_ppe_norm import PositionPpeNorm

from app.db.session import async_session_maker

async def fix():
    async with async_session_maker() as db:
        result = await db.execute(select(PpeCategory))
        categories = result.scalars().all()
        
        for cat in categories:
            new_name = cat.name.capitalize()
            if cat.name != new_name:
                print(f"Обновление: '{cat.name}' -> '{new_name}'")
                cat.name = new_name
        
        await db.commit()
        print("✅ Регистр категорий исправлен.")

if __name__ == "__main__":
    asyncio.run(fix())
EOF

echo "🚀 Копируем и запускаем скрипт..."
docker compose cp fix_case.py api:/app/fix_case.py
docker compose exec -T api python fix_case.py

echo "🧹 Удаляем временный файл..."
rm fix_case.py

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: import all models in fix_case.py"
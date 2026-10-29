#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем API сотрудников (фильтрация по подразделению)..."

cat > app/api/v1/endpoints/employees.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.exc import StaleDataError

from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_item import PpeItem
from app.models.ppe_category import PpeCategory
from app.models.user import User
from app.core.deps import get_current_active_user, get_current_user
from app.schemas.employee import EmployeeCreate, EmployeeRead, EmployeeUpdate

router = APIRouter(prefix="/employees", tags=["Сотрудники"])


def employee_options():
    return [
        selectinload(Employee.ppe_sizes).selectinload(EmployeePpeSize.category),
        selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item).selectinload(PpeItem.category),
        selectinload(Employee.department_rel),
        selectinload(Employee.position_rel)
    ]


async def get_employee_with_relations(db: AsyncSession, employee_id: int) -> Employee:
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id).options(*employee_options())
    )
    return result.scalar_one()


@router.post("/", response_model=EmployeeRead, status_code=status.HTTP_201_CREATED)
async def create_employee(
    employee_in: EmployeeCreate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    # Проверка прав: safety_officer может создавать только в своем подразделении
    if current_user.role == "safety_officer":
        if current_user.department_id != employee_in.department_id:
            raise HTTPException(status_code=403, detail="Вы можете создавать сотрудников только в своем подразделении")

    result = await db.execute(select(Employee).where(Employee.personnel_number == employee_in.personnel_number))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Сотрудник с таким табельным номером уже существует")

    employee_data = employee_in.model_dump(exclude={"ppe_sizes"})
    db_employee = Employee(**employee_data)
    db.add(db_employee)
    await db.flush()

    if employee_in.ppe_sizes:
        cat_ids = [size.category_id for size in employee_in.ppe_sizes]
        cats_result = await db.execute(select(PpeCategory.id).where(PpeCategory.id.in_(cat_ids)))
        if set(cat_ids) - set(cats_result.scalars().all()):
            await db.rollback()
            raise HTTPException(status_code=404, detail="Категории СИЗ не найдены")
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, category_id=size_data.category_id, size_value=size_data.size_value))

    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "employee_created", "employee_id": db_employee.id})
    except Exception:
        pass

    return await get_employee_with_relations(db, db_employee.id)


@router.get("/", response_model=list[EmployeeRead])
async def get_employees(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    query = select(Employee).options(*employee_options())
    
    # Фильтрация для safety_officer
    if current_user.role == "safety_officer" and current_user.department_id:
        if current_user.include_subdepartments:
            # Если включены дочерние подразделения, берем все сотрудники, чей department_id входит в список доступных
            # Пока реализуем простую версию: только его подразделение. 
            # Для иерархии нужно рекурсивно собрать все дочерние ID.
            # (Упрощенно: только его department_id)
            query = query.where(Employee.department_id == current_user.department_id)
        else:
            query = query.where(Employee.department_id == current_user.department_id)

    result = await db.execute(query)
    return result.scalars().all()


@router.get("/{employee_id}", response_model=EmployeeRead)
async def get_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    employee = await get_employee_with_relations(db, employee_id)
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")
    
    # Проверка прав на просмотр
    if current_user.role == "safety_officer" and current_user.department_id != employee.department_id:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    return employee


@router.put("/{employee_id}", response_model=EmployeeRead)
async def update_employee(
    employee_id: int, 
    employee_in: EmployeeUpdate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    db_employee = result.scalar_one_or_none()
    if not db_employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    # Проверка прав на редактирование
    if current_user.role == "safety_officer" and current_user.department_id != db_employee.department_id:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    if db_employee.version != employee_in.version:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Данные устарели")

    update_data = employee_in.model_dump(exclude_unset=True, exclude={"version", "ppe_sizes"})
    for field, value in update_data.items():
        setattr(db_employee, field, value)

    if employee_in.ppe_sizes is not None:
        await db.execute(delete(EmployeePpeSize).where(EmployeePpeSize.employee_id == employee_id))
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, category_id=size_data.category_id, size_value=size_data.size_value))

    try:
        await db.commit()
    except StaleDataError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Конфликт версий")

    try:
        await manager.broadcast_to_employee(employee_id, {"event": "employee_updated", "employee_id": employee_id})
    except Exception:
        pass

    return await get_employee_with_relations(db, employee_id)


@router.delete("/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    result = await db.execute(select(Employee).where(Employee.id == employee_id))
    db_employee = result.scalar_one_or_none()
    if not db_employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    if current_user.role == "safety_officer" and current_user.department_id != db_employee.department_id:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    try:
        await db.delete(db_employee)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")

    try:
        await manager.broadcast_to_employee(0, {"event": "employee_updated", "employee_id": employee_id})
    except Exception:
        pass
EOF

echo "🔧 Защищаем HTML-маршруты в main.py (редирект на /login)..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Функция-хелпер для проверки сессии
# Вставляем в начало файла после импортов
helper = '''
def check_auth(request: Request):
    """Проверяет наличие сессии. Если нет — возвращает RedirectResponse."""
    if not request.session.get("user_id"):
        return RedirectResponse(url="/login", status_code=303)
    return None
'''

if 'def check_auth' not in content:
    # Вставляем после импортов (после BASE_DIR)
    content = content.replace(
        'BASE_DIR = Path(__file__).resolve().parent',
        'BASE_DIR = Path(__file__).resolve().parent\n' + helper
    )

# Теперь добавляем проверку в каждый HTML-маршрут (кроме /login и /)
import re

# Список маршрутов, которые нужно защитить
protected_routes = [
    '/employees', '/employees/{employee_id}/edit',
    '/ppe-categories', '/ppe-categories/{category_id}/edit',
    '/ppe-items', '/ppe-items/{item_id}/edit',
    '/departments', '/departments/{dept_id}/edit',
    '/positions', '/positions/{pos_id}/edit',
    '/norms', '/settings'
]

# Для каждого маршрута добавляем проверку в начало функции
for route in protected_routes:
    # Ищем функцию с этим маршрутом
    pattern = r'(@app\.get\("' + re.escape(route) + r'", response_class=HTMLResponse\)\s*async def \w+\(request: Request[^)]*\):)(\s*)'
    match = re.search(pattern, content)
    if match:
        # Добавляем проверку после объявления функции
        replacement = match.group(1) + '\n    redirect = check_auth(request)\n    if redirect: return redirect' + match.group(2)
        content = content.replace(match.group(0), replacement)

with open('app/main.py', 'w') as f:
    f.write(content)
print("✅ HTML-маршруты защищены (редирект на /login).")
PYEOF

echo "🔧 Обновляем навбар (добавляем кнопку 'Выйти')..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Добавляем кнопку "Выйти" перед закрытием навбара
logout_btn = '''
            <ul class="navbar-nav ms-auto">
                <li class="nav-item">
                    <a class="nav-link" href="/api/v1/auth/logout" onclick="event.preventDefault(); fetch('/api/v1/auth/logout', {method: 'POST'}).then(() => window.location.href='/login');">Выйти</a>
                </li>
            </ul>
'''

if 'Выйти' not in content:
    content = content.replace(
        '            </ul>\n        </div>\n    </div>\n</nav>',
        '            </ul>' + logout_btn + '\n        </div>\n    </div>\n</nav>'
    )

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Кнопка 'Выйти' добавлена в навбар.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: protect routes, filter by department, add logout"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем эндпоинт для импорта сотрудников из Excel..."

cat > app/api/v1/endpoints/import_data.py << 'EOF'
import pandas as pd
from io import BytesIO
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.employee import Employee
from app.models.department import Department
from app.models.position import Position

router = APIRouter(prefix="/import", tags=["Импорт данных"])

@router.post("/employees")
async def import_employees(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    if not file.filename.endswith(('.xlsx', '.xls')):
        raise HTTPException(status_code=400, detail="Пожалуйста, загрузите файл Excel (.xlsx или .xls)")

    try:
        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")

    # Проверяем обязательные колонки
    required_cols = ["Табельный номер", "Фамилия", "Имя"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    created_count = 0
    updated_count = 0
    errors = []

    for index, row in df.iterrows():
        try:
            personnel_number = str(row["Табельный номер"]).strip()
            last_name = str(row["Фамилия"]).strip()
            first_name = str(row["Имя"]).strip()
            middle_name = str(row.get("Отчество", "")).strip() if pd.notna(row.get("Отчество")) else None
            
            # Проверяем, существует ли сотрудник
            result = await db.execute(select(Employee).where(Employee.personnel_number == personnel_number))
            db_employee = result.scalar_one_or_none()

            # Ищем подразделение и должность (если указаны)
            department_name = str(row.get("Подразделение", "")).strip() if pd.notna(row.get("Подразделение")) else ""
            position_name = str(row.get("Должность", "")).strip() if pd.notna(row.get("Должность")) else ""

            department_id = None
            if department_name:
                dept_res = await db.execute(select(Department).where(Department.name == department_name))
                dept = dept_res.scalar_one_or_none()
                if not dept:
                    dept = Department(name=department_name)
                    db.add(dept)
                    await db.flush()
                department_id = dept.id

            position_id = None
            if position_name and department_id:
                pos_res = await db.execute(select(Position).where(Position.name == position_name, Position.department_id == department_id))
                pos = pos_res.scalar_one_or_none()
                if not pos:
                    pos = Position(name=position_name, department_id=department_id)
                    db.add(pos)
                    await db.flush()
                position_id = pos.id

            if db_employee:
                # Обновляем существующего
                db_employee.last_name = last_name
                db_employee.first_name = first_name
                db_employee.middle_name = middle_name
                db_employee.department_id = department_id
                db_employee.position_id = position_id
                updated_count += 1
            else:
                # Создаем нового
                new_emp = Employee(
                    personnel_number=personnel_number,
                    last_name=last_name,
                    first_name=first_name,
                    middle_name=middle_name,
                    department_id=department_id,
                    position_id=position_id,
                    version=1
                )
                db.add(new_emp)
                created_count += 1
                
        except Exception as e:
            errors.append(f"Строка {index + 2}: {str(e)}")

    await db.commit()

    return {
        "message": "Импорт завершен",
        "created": created_count,
        "updated": updated_count,
        "errors": errors
    }
EOF

echo "🔧 Подключаем роутер импорта в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

if 'import_data' not in content:
    content = content.replace(
        'position_ppe_norms, employee_ppe_issues, ppe_sizes, export',
        'position_ppe_norms, employee_ppe_issues, ppe_sizes, export, import_data'
    )
    content = content.replace(
        'app.include_router(export.router, prefix="/api/v1")',
        'app.include_router(export.router, prefix="/api/v1")\napp.include_router(import_data.router, prefix="/api/v1")'
    )
    print("✅ main.py обновлен (добавлен импорт).")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Обновляем страницу настроек (логика отправки файла)..."

python3 - << 'PYEOF'
with open('app/templates/settings.html', 'r') as f:
    content = f.read()

# Заменяем заглушку на реальную логику
old_script = '''<script>
  // Заглушка для импорта (логика будет добавлена позже)
  document.getElementById('import-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    window.showToast('Импорт пока не реализован, но форма готова!', 'info');
    document.getElementById('import-result').innerHTML = '<div class="alert alert-warning">Функция импорта скоро появится.</div>';
  });
</script>'''

new_script = '''<script>
  document.getElementById('import-form')?.addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.target;
    const fileInput = form.querySelector('input[type="file"]');
    const resultDiv = document.getElementById('import-result');
    const btn = document.getElementById('import-btn');

    if (!fileInput.files.length) {
        window.showToast('Выберите файл', 'warning');
        return;
    }

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    btn.disabled = true;
    btn.textContent = 'Загрузка...';
    resultDiv.innerHTML = '';

    try {
        const resp = await fetch('/api/v1/import/employees', {
            method: 'POST',
            body: formData
        });

        const data = await resp.json();

        if (!resp.ok) {
            throw new Error(data.detail || 'Ошибка импорта');
        }

        let html = `<div class="alert alert-success">
            <strong>Импорт завершен!</strong><br>
            Создано: ${data.created}, Обновлено: ${data.updated}
        </div>`;

        if (data.errors && data.errors.length > 0) {
            html += `<div class="alert alert-warning mt-2">
                <strong>Ошибки:</strong><br>
                ${data.errors.join('<br>')}
            </div>`;
        }

        resultDiv.innerHTML = html;
        window.showToast('Импорт выполнен', 'success');
        form.reset();
    } catch (err) {
        resultDiv.innerHTML = `<div class="alert alert-danger">${err.message}</div>`;
        window.showToast(err.message, 'danger');
    } finally {
        btn.disabled = false;
        btn.textContent = 'Загрузить';
    }
  });
</script>'''

content = content.replace(old_script, new_script)

# Убираем информационное сообщение о том, что импорт в разработке
content = content.replace(
    '<div class="alert alert-info">\n            <i class="bi bi-info-circle"></i> \n            Раздел импорта находится в разработке (доступен только интерфейс). В ближайшем обновлении будет добавлена логика загрузки.\n        </div>',
    ''
)

with open('app/templates/settings.html', 'w') as f:
    f.write(content)
print("✅ Страница настроек обновлена (логика импорта).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: implement employee import from Excel"
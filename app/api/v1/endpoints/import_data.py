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

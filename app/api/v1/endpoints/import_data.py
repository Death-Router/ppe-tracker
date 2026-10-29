import pandas as pd
from io import BytesIO
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.employee import Employee
from app.models.department import Department
from app.models.position import Position
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.position_ppe_norm import PositionPpeNorm

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
        if 'ID' in df.columns:
            df = df.drop(columns=['ID'])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")

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
            
            result = await db.execute(select(Employee).where(Employee.personnel_number == personnel_number))
            db_employee = result.scalar_one_or_none()

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
                db_employee.last_name = last_name
                db_employee.first_name = first_name
                db_employee.middle_name = middle_name
                db_employee.department_id = department_id
                db_employee.position_id = position_id
                updated_count += 1
            else:
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
    return {"message": "Импорт завершен", "created": created_count, "updated": updated_count, "errors": errors}


@router.post("/ppe-items")
async def import_ppe_items(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    if not file.filename.endswith(('.xlsx', '.xls')):
        raise HTTPException(status_code=400, detail="Пожалуйста, загрузите файл Excel")

    try:
        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
        if 'ID' in df.columns:
            df = df.drop(columns=['ID'])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")

    required_cols = ["Наименование", "Категория"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    created_count = 0
    errors = []

    for index, row in df.iterrows():
        try:
            name = str(row["Наименование"]).strip()
            category_name = str(row["Категория"]).strip()

            # Ищем категорию
            cat_res = await db.execute(select(PpeCategory).where(PpeCategory.name == category_name))
            category = cat_res.scalar_one_or_none()
            if not category:
                category = PpeCategory(name=category_name)
                db.add(category)
                await db.flush()

            # Проверяем, есть ли уже такое СИЗ в этой категории
            item_res = await db.execute(select(PpeItem).where(PpeItem.name == name, PpeItem.category_id == category.id))
            existing = item_res.scalar_one_or_none()
            if not existing:
                new_item = PpeItem(name=name, category_id=category.id, version=1)
                db.add(new_item)
                created_count += 1
        except Exception as e:
            errors.append(f"Строка {index + 2}: {str(e)}")

    await db.commit()
    return {"message": "Импорт СИЗ завершен", "created": created_count, "errors": errors}


@router.post("/norms")
async def import_norms(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    if not file.filename.endswith(('.xlsx', '.xls')):
        raise HTTPException(status_code=400, detail="Пожалуйста, загрузите файл Excel")

    try:
        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
        if 'ID' in df.columns:
            df = df.drop(columns=['ID'])
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")

    required_cols = ["Подразделение", "Должность", "СИЗ", "Срок", "Количество"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    created_count = 0
    errors = []

    for index, row in df.iterrows():
        try:
            dept_name = str(row["Подразделение"]).strip()
            pos_name = str(row["Должность"]).strip()
            item_name = str(row["СИЗ"]).strip()
            period_str = str(row["Срок"]).strip()
            quantity = str(row["Количество"]).strip()

            # Ищем подразделение
            dept_res = await db.execute(select(Department).where(Department.name == dept_name))
            dept = dept_res.scalar_one_or_none()
            if not dept:
                errors.append(f"Строка {index + 2}: Подразделение '{dept_name}' не найдено")
                continue

            # Ищем должность
            pos_res = await db.execute(select(Position).where(Position.name == pos_name, Position.department_id == dept.id))
            pos = pos_res.scalar_one_or_none()
            if not pos:
                errors.append(f"Строка {index + 2}: Должность '{pos_name}' не найдена в '{dept_name}'")
                continue

            # Ищем СИЗ
            item_res = await db.execute(select(PpeItem).where(PpeItem.name == item_name))
            item = item_res.scalar_one_or_none()
            if not item:
                errors.append(f"Строка {index + 2}: СИЗ '{item_name}' не найдено")
                continue

            # Парсим срок (например "1 год" или "12 месяцев")
            parts = period_str.split()
            if len(parts) != 2:
                errors.append(f"Строка {index + 2}: Неверный формат срока '{period_str}'")
                continue
            period_value, period_unit = parts

            # Проверяем, нет ли уже такой нормы
            norm_res = await db.execute(select(PositionPpeNorm).where(
                PositionPpeNorm.position_id == pos.id,
                PositionPpeNorm.ppe_item_id == item.id
            ))
            existing = norm_res.scalar_one_or_none()

            if existing:
                existing.wear_period_value = period_value
                existing.wear_period_unit = period_unit
                existing.quantity = quantity
            else:
                new_norm = PositionPpeNorm(
                    position_id=pos.id,
                    ppe_item_id=item.id,
                    wear_period_value=period_value,
                    wear_period_unit=period_unit,
                    quantity=quantity,
                    version=1
                )
                db.add(new_norm)
                created_count += 1
        except Exception as e:
            errors.append(f"Строка {index + 2}: {str(e)}")

    await db.commit()
    return {"message": "Импорт норм завершен", "created": created_count, "errors": errors}

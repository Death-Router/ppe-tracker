import pandas as pd
from io import BytesIO
from fastapi import APIRouter, UploadFile, File, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.models.employee import Employee
from app.models.department import Department
from app.models.position import Position
from app.models.ppe_item import PpeItem
from app.models.ppe_function import PpeFunction
from app.models.ppe_size_group import PpeSizeGroup
from app.models.unit import Unit
from app.models.position_ppe_norm import PositionPpeNorm

router = APIRouter(prefix="/import", tags=["Импорт данных"])

def safe_str(val):
    if pd.isna(val) or val is None:
        return ""
    return str(val).strip()

@router.post("/employees")
async def import_employees(
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

    required_cols = ["Табельный номер", "Фамилия", "Имя"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    created_count = 0
    updated_count = 0
    errors = []

    for index, row in df.iterrows():
        try:
            personnel_number = safe_str(row["Табельный номер"])
            last_name = safe_str(row["Фамилия"])
            first_name = safe_str(row["Имя"])
            middle_name = safe_str(row.get("Отчество", "")) or None
            
            result = await db.execute(select(Employee).where(Employee.personnel_number == personnel_number))
            db_employee = result.scalar_one_or_none()

            department_name = safe_str(row.get("Подразделение", ""))
            position_name = safe_str(row.get("Должность", ""))

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

    # Поддерживаем разные варианты названий колонок
    col_name = 'Наименование' if 'Наименование' in df.columns else 'Наименование СИЗ'
    col_func = 'Функция' if 'Функция' in df.columns else None
    col_group = 'Размерная группа' if 'Размерная группа' in df.columns else None
    col_unit = 'Единица измерения' if 'Единица измерения' in df.columns else None

    if col_name not in df.columns:
        raise HTTPException(status_code=400, detail="В файле отсутствует колонка 'Наименование'")

    created_count = 0
    errors = []

    for index, row in df.iterrows():
        try:
            name = safe_str(row[col_name])
            if not name:
                errors.append(f"Строка {index + 2}: Пустое наименование")
                continue
            
            if len(name) > 255:
                name = name[:252] + "..."
                errors.append(f"Строка {index + 2}: Название обрезано до 255 символов")

            # Обрабатываем функцию
            function_id = None
            if col_func and safe_str(row.get(col_func, "")):
                func_name = safe_str(row[col_func])
                func_res = await db.execute(select(PpeFunction).where(PpeFunction.name == func_name))
                func = func_res.scalar_one_or_none()
                if not func:
                    func = PpeFunction(name=func_name)
                    db.add(func)
                    await db.flush()
                function_id = func.id

            # Обрабатываем размерную группу
            size_group_id = None
            if col_group and safe_str(row.get(col_group, "")):
                group_name = safe_str(row[col_group])
                group_res = await db.execute(select(PpeSizeGroup).where(PpeSizeGroup.name == group_name))
                group = group_res.scalar_one_or_none()
                if not group:
                    group = PpeSizeGroup(name=group_name)
                    db.add(group)
                    await db.flush()
                size_group_id = group.id

            # Обрабатываем единицу измерения
            unit_id = None
            if col_unit and safe_str(row.get(col_unit, "")):
                unit_short = safe_str(row[col_unit])
                unit_res = await db.execute(select(Unit).where(Unit.short_name == unit_short))
                unit = unit_res.scalar_one_or_none()
                if unit:
                    unit_id = unit.id
                else:
                    errors.append(f"Строка {index + 2}: Единица измерения '{unit_short}' не найдена")

            # Проверяем, есть ли уже такое СИЗ
            item_res = await db.execute(select(PpeItem).where(PpeItem.name == name))
            existing = item_res.scalar_one_or_none()
            
            if existing:
                existing.function_id = function_id
                existing.size_group_id = size_group_id
                existing.unit_id = unit_id
            else:
                new_item = PpeItem(
                    name=name, 
                    function_id=function_id, 
                    size_group_id=size_group_id,
                    unit_id=unit_id,
                    version=1
                )
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
            dept_name = safe_str(row["Подразделение"])
            pos_name = safe_str(row["Должность"])
            item_name = safe_str(row["СИЗ"])
            period_str = safe_str(row["Срок"])
            quantity = safe_str(row["Количество"])

            dept_res = await db.execute(select(Department).where(Department.name == dept_name))
            dept = dept_res.scalar_one_or_none()
            if not dept:
                errors.append(f"Строка {index + 2}: Подразделение '{dept_name}' не найдено")
                continue

            pos_res = await db.execute(select(Position).where(Position.name == pos_name, Position.department_id == dept.id))
            pos = pos_res.scalar_one_or_none()
            if not pos:
                errors.append(f"Строка {index + 2}: Должность '{pos_name}' не найдена в '{dept_name}'")
                continue

            item_res = await db.execute(select(PpeItem).where(PpeItem.name == item_name))
            item = item_res.scalar_one_or_none()
            if not item:
                errors.append(f"Строка {index + 2}: СИЗ '{item_name}' не найдено")
                continue

            parts = period_str.split()
            if len(parts) != 2:
                errors.append(f"Строка {index + 2}: Неверный формат срока '{period_str}'")
                continue
            period_value, period_unit = parts

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

import pandas as pd
from io import BytesIO

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
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

CHUNK_SIZE = 1024 * 1024
MAX_ERRORS = 50


def safe_str(val):
    if val is None or pd.isna(val):
        return ""
    return str(val).strip()


async def read_table(file: UploadFile) -> pd.DataFrame:
    """Читает Excel с ограничениями по размеру файла и числу строк.

    Файл читается порциями: без этого `await file.read()` тянул в память
    что угодно, а pandas ещё и разворачивал это в DataFrame.
    """
    name = (file.filename or "").lower()

    if name.endswith(".xls"):
        raise HTTPException(
            status_code=400,
            detail="Формат .xls не поддерживается. Откройте файл в Excel и сохраните как .xlsx",
        )
    if not name.endswith(".xlsx"):
        raise HTTPException(status_code=400, detail="Нужен файл Excel в формате .xlsx")

    limit = settings.MAX_IMPORT_FILE_MB * 1024 * 1024
    chunks: list[bytes] = []
    total = 0

    while True:
        chunk = await file.read(CHUNK_SIZE)
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise HTTPException(
                status_code=413,
                detail=f"Файл больше {settings.MAX_IMPORT_FILE_MB} МБ",
            )
        chunks.append(chunk)

    if total == 0:
        raise HTTPException(status_code=400, detail="Файл пустой")

    try:
        df = pd.read_excel(BytesIO(b"".join(chunks)))
    except Exception as exc:  # noqa: BLE001 — текст ошибки уходит пользователю
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {exc}")

    if len(df) > settings.MAX_IMPORT_ROWS:
        raise HTTPException(
            status_code=413,
            detail=f"В файле {len(df)} строк, максимум {settings.MAX_IMPORT_ROWS}",
        )

    if "ID" in df.columns:
        df = df.drop(columns=["ID"])

    return df


def add_error(errors: list[str], message: str) -> None:
    """Копим не больше MAX_ERRORS сообщений, чтобы ответ не разросся."""
    if len(errors) < MAX_ERRORS:
        errors.append(message)


async def run_rows(db: AsyncSession, df: pd.DataFrame, handler) -> tuple[dict, list[str]]:
    """Выполняет обработчик для каждой строки в отдельной SAVEPOINT.

    Без savepoint первая же ошибка ломала сессию: все последующие строки
    падали с PendingRollbackError, и импорт «терял» остаток файла.
    """
    counters = {"created": 0, "updated": 0}
    errors: list[str] = []

    for index, row in df.iterrows():
        try:
            async with db.begin_nested():
                await handler(row, counters)
        except Exception as exc:  # noqa: BLE001 — сообщение показываем пользователю
            add_error(errors, f"Строка {index + 2}: {exc}")

    await db.commit()
    return counters, errors


@router.post("/employees")
async def import_employees(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    df = await read_table(file)

    required_cols = ["Табельный номер", "Фамилия", "Имя"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    async def handle_row(row, counters):
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
            pos_res = await db.execute(
                select(Position).where(
                    Position.name == position_name,
                    Position.department_id == department_id,
                )
            )
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
            counters["updated"] += 1
        else:
            db.add(
                Employee(
                    personnel_number=personnel_number,
                    last_name=last_name,
                    first_name=first_name,
                    middle_name=middle_name,
                    department_id=department_id,
                    position_id=position_id,
                    version=1,
                )
            )
            counters["created"] += 1

    counters, errors = await run_rows(db, df, handle_row)
    return {
        "message": "Импорт завершен",
        "created": counters["created"],
        "updated": counters["updated"],
        "errors": errors,
    }


@router.post("/ppe-items")
async def import_ppe_items(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    df = await read_table(file)

    col_name = "Наименование" if "Наименование" in df.columns else "Наименование СИЗ"
    col_func = "Функция" if "Функция" in df.columns else None
    col_group = "Размерная группа" if "Размерная группа" in df.columns else None
    col_unit = "Единица измерения" if "Единица измерения" in df.columns else None

    if col_name not in df.columns:
        raise HTTPException(status_code=400, detail="В файле отсутствует колонка 'Наименование'")

    async def handle_row(row, counters):
        name = safe_str(row[col_name])
        if not name:
            raise ValueError("Пустое наименование")

        if len(name) > 255:
            name = name[:255]

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

        unit_id = None
        if col_unit and safe_str(row.get(col_unit, "")):
            unit_short = safe_str(row[col_unit])
            unit_res = await db.execute(select(Unit).where(Unit.short_name == unit_short))
            unit = unit_res.scalar_one_or_none()
            if not unit:
                raise ValueError(f"Единица измерения '{unit_short}' не найдена")
            unit_id = unit.id

        item_res = await db.execute(select(PpeItem).where(PpeItem.name == name))
        existing = item_res.scalar_one_or_none()

        if existing:
            existing.function_id = function_id
            existing.size_group_id = size_group_id
            existing.unit_id = unit_id
        else:
            db.add(
                PpeItem(
                    name=name,
                    function_id=function_id,
                    size_group_id=size_group_id,
                    unit_id=unit_id,
                    version=1,
                )
            )
            counters["created"] += 1

    counters, errors = await run_rows(db, df, handle_row)
    return {
        "message": "Импорт СИЗ завершен",
        "created": counters["created"],
        "errors": errors,
    }


@router.post("/norms")
async def import_norms(
    file: UploadFile = File(...), db: AsyncSession = Depends(get_db)
):
    df = await read_table(file)

    required_cols = ["Подразделение", "Должность", "СИЗ", "Срок", "Количество"]
    for col in required_cols:
        if col not in df.columns:
            raise HTTPException(status_code=400, detail=f"В файле отсутствует колонка: {col}")

    async def handle_row(row, counters):
        dept_name = safe_str(row["Подразделение"])
        pos_name = safe_str(row["Должность"])
        item_name = safe_str(row["СИЗ"])
        period_str = safe_str(row["Срок"])
        quantity = safe_str(row["Количество"])

        dept_res = await db.execute(select(Department).where(Department.name == dept_name))
        dept = dept_res.scalar_one_or_none()
        if not dept:
            raise ValueError(f"Подразделение '{dept_name}' не найдено")

        pos_res = await db.execute(
            select(Position).where(
                Position.name == pos_name,
                Position.department_id == dept.id,
            )
        )
        pos = pos_res.scalar_one_or_none()
        if not pos:
            raise ValueError(f"Должность '{pos_name}' не найдена в '{dept_name}'")

        item_res = await db.execute(select(PpeItem).where(PpeItem.name == item_name))
        item = item_res.scalar_one_or_none()
        if not item:
            raise ValueError(f"СИЗ '{item_name}' не найдено")

        parts = period_str.split()
        if len(parts) != 2:
            raise ValueError(f"Неверный формат срока '{period_str}', нужно например '1 год'")
        period_value, period_unit = parts

        norm_res = await db.execute(
            select(PositionPpeNorm).where(
                PositionPpeNorm.position_id == pos.id,
                PositionPpeNorm.ppe_item_id == item.id,
            )
        )
        existing = norm_res.scalar_one_or_none()

        if existing:
            existing.wear_period_value = period_value
            existing.wear_period_unit = period_unit
            existing.quantity = quantity
            counters["updated"] += 1
        else:
            db.add(
                PositionPpeNorm(
                    position_id=pos.id,
                    ppe_item_id=item.id,
                    wear_period_value=period_value,
                    wear_period_unit=period_unit,
                    quantity=quantity,
                    version=1,
                )
            )
            counters["created"] += 1

    counters, errors = await run_rows(db, df, handle_row)
    return {
        "message": "Импорт норм завершен",
        "created": counters["created"],
        "updated": counters["updated"],
        "errors": errors,
    }

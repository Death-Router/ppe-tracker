from decimal import Decimal, InvalidOperation

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.versioning import ensure_version
from app.db.session import get_db
from app.models.employee import Employee
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.ppe_item import PpeItem
from app.schemas.employee_ppe_issue import (
    EmployeePpeIssueCreate,
    EmployeePpeIssueRead,
    EmployeePpeIssueUpdate,
)
from app.utils.broadcast import broadcast
from app.utils.dates import add_wear_period


def issue_item_options():
    """Жадно грузим СИЗ со всеми связями схемы PpeItemRead.

    Без unit сериализация уходила в ленивую загрузку, а в async-SQLAlchemy
    это MissingGreenlet и 500 — так падал список выдач и карточка сотрудника.
    """
    item = selectinload(EmployeePpeIssue.ppe_item)
    return [
        item.selectinload(PpeItem.function),
        item.selectinload(PpeItem.size_group),
        item.selectinload(PpeItem.unit),
    ]


router = APIRouter(prefix="/employee_ppe_issues", tags=["Выдача СИЗ"])


def parse_quantity(raw: str | None, label: str) -> Decimal:
    """Разбирает количество из карточки: «2», «2,5», « 2 » — это числа.

    В БД количество хранится строкой (в нормах встречаются записи вида «1 пара»),
    но остаток по такой записи не посчитать. Поэтому строка обязана быть числом,
    иначе честно говорим об этом, а не пропускаем отрицательный остаток.
    """
    text = (raw or "").replace("\u00a0", " ").replace(",", ".").strip()
    try:
        value = Decimal(text)
    except InvalidOperation:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Количество «{label}» = «{raw}» — это не число. "
                "Остаток не посчитать: укажите количество цифрами."
            ),
        ) from None

    if value <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Количество «{label}» должно быть больше нуля",
        )
    return value


def ensure_balance_not_negative(quantity: str, returned_quantity: str) -> None:
    """Остаток = выдано − возвращено. Он не может уйти в минус.

    Иначе в карточке появляется «выдано 2, возвращено 6», и по такому остатку
    уже не понять, сколько СИЗ реально на руках.
    """
    issued = parse_quantity(quantity, "выдано")
    returned = parse_quantity(returned_quantity, "возвращено")
    if returned > issued:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Возврат больше выдачи: выдано {issued.normalize():f}, "
                f"возвращают {returned.normalize():f}. "
                "Остаток не может быть отрицательным."
            ),
        )


@router.post("/", response_model=EmployeePpeIssueRead, status_code=status.HTTP_201_CREATED)
async def create_issue(issue_in: EmployeePpeIssueCreate, db: AsyncSession = Depends(get_db)):
    # 1. Проверяем сотрудника
    emp_res = await db.execute(select(Employee).where(Employee.id == issue_in.employee_id))
    employee = emp_res.scalar_one_or_none()
    if not employee:
        raise HTTPException(status_code=404, detail="Сотрудник не найден")

    # 2. Проверяем СИЗ
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == issue_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    # 3. Рассчитываем срок годности на основе нормы для должности сотрудника
    expiry_date = None
    if employee.position_id:
        # Норм на пару «должность + СИЗ» может быть несколько: в матрице
        # норм есть основное наименование и альтернативы. scalar_one_or_none
        # тут падал бы MultipleResultsFound, поэтому берём первую.
        norm_res = await db.execute(
            select(PositionPpeNorm)
            .where(
                PositionPpeNorm.position_id == employee.position_id,
                PositionPpeNorm.ppe_item_id == issue_in.ppe_item_id,
            )
            .order_by(PositionPpeNorm.id)
            .limit(1)
        )
        norm = norm_res.scalars().first()
        if norm:
            expiry_date = add_wear_period(
                issue_in.issue_date, norm.wear_period_value, norm.wear_period_unit
            )

    # 4. Создаем запись
    # Возврат может прийти сразу вместе с выдачей (импорт/API) — остаток
    # проверяем тем же правилом, что и при правке
    if issue_in.returned_quantity:
        ensure_balance_not_negative(issue_in.quantity, issue_in.returned_quantity)

    db_issue = EmployeePpeIssue(
        employee_id=issue_in.employee_id,
        ppe_item_id=issue_in.ppe_item_id,
        issue_date=issue_in.issue_date,
        quantity=issue_in.quantity,
        size_value=issue_in.size_value,
        # Способ выдачи заполняется сразу: «дозатор» у дерматологических СИЗ
        # известен в момент выдачи, позже его пришлось бы восстанавливать
        issue_method=issue_in.issue_method,
        expiry_date=expiry_date
    )
    db.add(db_issue)
    await db.commit()
    await db.refresh(db_issue)

    # Вкладка со списком сотрудников держит выдачи в памяти: без события
    # новая запись появлялась только после ручного обновления страницы
    await broadcast(0, {"event": "issue_updated", "employee_id": db_issue.employee_id})

    # 5. Загружаем связи для ответа
    result = await db.execute(
        select(EmployeePpeIssue).where(EmployeePpeIssue.id == db_issue.id)
        .options(*issue_item_options())
    )
    return result.scalar_one()


@router.get("/", response_model=list[EmployeePpeIssueRead])
async def get_issues(employee_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(EmployeePpeIssue).where(EmployeePpeIssue.employee_id == employee_id)
        .options(*issue_item_options())
    )
    return result.scalars().all()


@router.put("/{issue_id}", response_model=EmployeePpeIssueRead)
async def update_issue(
    issue_id: int, issue_in: EmployeePpeIssueUpdate, db: AsyncSession = Depends(get_db)
):
    """Возврат СИЗ и акт списания — графы 7-10 оборотной стороны карточки.

    Дату выдачи, размер и количество здесь менять нельзя: это факт выдачи,
    он уже отражён в личной карточке. Правка задним числом — через удаление
    записи и новую выдачу, чтобы в истории не появлялось подменённых данных.
    """
    result = await db.execute(select(EmployeePpeIssue).where(EmployeePpeIssue.id == issue_id))
    db_issue = result.scalar_one_or_none()
    if not db_issue:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    ensure_version(db_issue.version, issue_in.version)

    update_data = issue_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_issue, field, value)

    # Пара «дата + количество» и пара «дата + номер акта» заполняются вместе:
    # акт без номера или возврат без даты в карточке не читаются
    if bool(db_issue.returned_date) != bool(db_issue.returned_quantity):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="У возврата должны быть и дата, и количество",
        )
    if bool(db_issue.write_off_act_date) != bool(db_issue.write_off_act_number):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="У акта списания должны быть и дата, и номер",
        )

    # Остаток меняется именно возвратом, поэтому проверяем его до записи
    if db_issue.returned_quantity:
        ensure_balance_not_negative(db_issue.quantity, db_issue.returned_quantity)

    db_issue.version += 1
    await db.commit()

    await broadcast(0, {"event": "issue_updated", "employee_id": db_issue.employee_id})

    result = await db.execute(
        select(EmployeePpeIssue)
        .where(EmployeePpeIssue.id == issue_id)
        .options(*issue_item_options())
    )
    return result.scalar_one()


@router.delete("/{issue_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_issue(issue_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(EmployeePpeIssue).where(EmployeePpeIssue.id == issue_id))
    db_issue = result.scalar_one_or_none()
    if not db_issue:
        raise HTTPException(status_code=404, detail="Запись не найдена")

    try:
        await db.delete(db_issue)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления") from exc

    await broadcast(0, {"event": "issue_updated", "employee_id": db_issue.employee_id})

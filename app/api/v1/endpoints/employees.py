from datetime import UTC, datetime

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse
from sqlalchemy import delete, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.exc import StaleDataError

from app.api import pagination
from app.api.db import commit_or_400, ensure_found
from app.api.versioning import ensure_version
from app.core.constants import height_error_message, is_height_from_grid
from app.core.deps import get_current_active_user
from app.core.photos import delete_photo_file, photo_path, store_employee_photo
from app.db.session import get_db
from app.models.department import Department
from app.models.employee import Employee
from app.models.employee_photo import EmployeePhoto
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.ppe_item import PpeItem
from app.models.ppe_size_group import PpeSizeGroup
from app.models.user import User
from app.schemas.employee import (
    EmployeeCreate,
    EmployeePhotoMeta,
    EmployeeRead,
    EmployeeUpdate,
)
from app.utils.broadcast import broadcast

router = APIRouter(prefix="/employees", tags=["Сотрудники"])


def employee_options():
    """Жадно загружаем всё, что попадает в ответ.

    Pydantic при сериализации обходит всю схему, и любой незагруженный
    relationship уходит в ленивую загрузку. В async-SQLAlchemy это
    невозможно и даёт MissingGreenlet — так падал список сотрудников,
    когда в схему добавилось ppe_issues с полем unit у СИЗ.
    """
    issue_item = selectinload(Employee.ppe_issues).selectinload(EmployeePpeIssue.ppe_item)
    return [
        selectinload(Employee.ppe_sizes).selectinload(EmployeePpeSize.size_group),
        # Схема PpeItemRead включает function, size_group и unit — грузим все три
        issue_item.selectinload(PpeItem.function),
        issue_item.selectinload(PpeItem.size_group),
        issue_item.selectinload(PpeItem.unit),
        selectinload(Employee.department_rel),
        selectinload(Employee.position_rel),
        # Без этого схема EmployeeRead.photo уходила в ленивую загрузку
        # и давала MissingGreenlet при сериализации карточки
        selectinload(Employee.photo),
    ]


async def get_employee_with_relations(db: AsyncSession, employee_id: int) -> Employee | None:
    result = await db.execute(
        select(Employee).where(Employee.id == employee_id).options(*employee_options())
    )
    # scalar_one() падал с NoResultFound (500) вместо 404 на несуществующем id
    return result.scalar_one_or_none()


def validate_height(height: str | None) -> None:
    """Рост должен быть из размерной сетки Положения.

    Проверяем здесь, а не в Pydantic: значение приходит из формы как текст,
    а ответ 422 с массивом ошибок клиент показывает как «HTTP 422» вместо
    объяснения, какой рост допустим.
    """
    if height and not is_height_from_grid(height):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=height_error_message(height),
        )


async def ensure_card_number_free(
    db: AsyncSession, card_number: str | None, employee_id: int | None = None
) -> None:
    """Номер личной карточки — номер документа, повторов быть не должно."""
    if not card_number:
        return

    query = select(Employee).where(Employee.personal_card_number == card_number)
    if employee_id is not None:
        # При правке сотрудник «занимает» свой же номер — это не конфликт
        query = query.where(Employee.id != employee_id)

    if (await db.execute(query)).scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Номер личной карточки «{card_number}» уже занят другим сотрудником",
        )


async def get_allowed_department_ids(db: AsyncSession, user: User) -> list[int]:

    """Возвращает список ID подразделений, доступных пользователю (с учётом иерархии)."""
    if user.role == "admin" or not user.department_id:
        return []  # Пустой список = без ограничений (все)

    allowed_ids = [user.department_id]
    
    if user.include_subdepartments:
        # Рекурсивно собираем дочерние подразделения
        result = await db.execute(select(Department))
        all_departments = result.scalars().all()
        
        def collect_children(parent_id):
            children = [d.id for d in all_departments if d.parent_id == parent_id]
            for child in children:
                allowed_ids.append(child)
                collect_children(child)
        
        collect_children(user.department_id)
    
    return allowed_ids


@router.post("/", response_model=EmployeeRead, status_code=status.HTTP_201_CREATED)
async def create_employee(
    employee_in: EmployeeCreate, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    if current_user.role == "safety_officer":
        allowed = await get_allowed_department_ids(db, current_user)
        if employee_in.department_id not in allowed:
            raise HTTPException(status_code=403, detail="Вы можете создавать сотрудников только в своем подразделении")

    result = await db.execute(select(Employee).where(Employee.personnel_number == employee_in.personnel_number))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Сотрудник с таким табельным номером уже существует")

    validate_height(employee_in.height)
    await ensure_card_number_free(db, employee_in.personal_card_number)

    employee_data = employee_in.model_dump(exclude={"ppe_sizes"})
    db_employee = Employee(**employee_data)
    db.add(db_employee)
    await db.flush()

    if employee_in.ppe_sizes:
        cat_ids = [size.size_group_id for size in employee_in.ppe_sizes]
        groups_result = await db.execute(select(PpeSizeGroup.id).where(PpeSizeGroup.id.in_(cat_ids)))
        if set(cat_ids) - set(groups_result.scalars().all()):
            await db.rollback()
            raise HTTPException(status_code=404, detail="Размерные группы не найдены")

        # Одна группа — один размер: две строки с одной группой не пройдут
        # уникальное ограничение, поэтому объясняем это до записи
        duplicates = {cid for cid in cat_ids if cat_ids.count(cid) > 1}
        if duplicates:
            group = await db.get(PpeSizeGroup, next(iter(duplicates)))
            group_name = group.name if group else "этой группы"
            await db.rollback()
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Размер для группы «{group_name}» указан дважды. "
                    "Для каждой размерной группы допускается только один размер."
                ),
            )

        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, size_group_id=size_data.size_group_id, size_value=size_data.size_value))

    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        # Проверки выше ловят обычные случаи; сюда попадает только гонка
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Не удалось сохранить сотрудника: табельный номер, номер личной "
                "карточки или размер по одной из групп уже заняты"
            ),
        ) from exc

    await broadcast(0, {"event": "employee_created", "employee_id": db_employee.id})

    employee = await get_employee_with_relations(db, db_employee.id)
    if employee is None:
        raise HTTPException(status_code=500, detail="Не удалось прочитать созданного сотрудника")
    return employee


@router.get("/", response_model=None)
async def get_employees(
    params: pagination.PageDep,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
    search: str | None = Query(None, description="Поиск по ФИО или табельному"),
    paginated: bool = Query(False, description="Вернуть страницу с метаданными"),
):
    """Список сотрудников.

    Без `paginated=true` отдаётся обычный массив — так работают выпадающие
    списки, которым нужны все значения сразу. С `paginated=true` приходит
    конверт со счётчиками и учитывается `search`.
    """
    conditions = []

    allowed = await get_allowed_department_ids(db, current_user)
    if allowed:
        conditions.append(Employee.department_id.in_(allowed))

    if search:
        pattern = f"%{search.strip().lower()}%"
        conditions.append(
            or_(
                func.lower(Employee.last_name).like(pattern),
                func.lower(Employee.first_name).like(pattern),
                func.lower(func.coalesce(Employee.middle_name, "")).like(pattern),
                func.lower(Employee.personnel_number).like(pattern),
            )
        )

    base = select(Employee).where(*conditions) if conditions else select(Employee)

    if not paginated:
        result = await db.execute(base.options(*employee_options()))
        # Через схему, а не ORM: иначе FastAPI отдаёт все атрибуты, включая
        # служебные поля фото (filename, sha256) — они клиенту не нужны
        return [EmployeeRead.model_validate(item) for item in result.scalars().all()]

    total = (
        await db.execute(select(func.count()).select_from(base.subquery()))
    ).scalar_one()
    query = pagination.apply(
        base.options(*employee_options())
        .order_by(Employee.last_name, Employee.first_name, Employee.id),
        params,
    )
    result = await db.execute(query)
    items = result.scalars().all()

    return pagination.page_of([EmployeeRead.model_validate(item) for item in items], total, params)


@router.get("/{employee_id}", response_model=EmployeeRead)
async def get_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    employee = ensure_found(
        await get_employee_with_relations(db, employee_id), "Сотрудник не найден"
    )
    
    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and employee.department_id not in allowed:
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
    db_employee = ensure_found(result.scalar_one_or_none(), "Сотрудник не найден")

    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and db_employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    ensure_version(db_employee.version, employee_in.version)

    update_data = employee_in.model_dump(exclude_unset=True, exclude={"version", "ppe_sizes"})

    validate_height(update_data.get("height"))
    await ensure_card_number_free(db, update_data.get("personal_card_number"), employee_id)

    for field, value in update_data.items():
        setattr(db_employee, field, value)

    # Без инкремента проверка версии выше пропускала бы любые параллельные правки
    db_employee.version += 1

    if employee_in.ppe_sizes is not None:
        # Одна размерная группа — один размер на сотрудника. Проверяем до
        # записи, иначе commit падал на уникальном ограничении и клиент видел
        # голое «HTTP 500» вместо объяснения.
        seen_groups: dict[int, int] = {}
        for index, size_data in enumerate(employee_in.ppe_sizes, start=1):
            previous = seen_groups.get(size_data.size_group_id)
            if previous is not None:
                group = await db.get(PpeSizeGroup, size_data.size_group_id)
                group_name = group.name if group else "этой группы"
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"Размер для группы «{group_name}» уже указан в строках "
                        f"{previous} и {index}. Для каждой размерной группы "
                        "допускается только один размер."
                    ),
                )
            seen_groups[size_data.size_group_id] = index

        await db.execute(delete(EmployeePpeSize).where(EmployeePpeSize.employee_id == employee_id))
        for size_data in employee_in.ppe_sizes:
            db.add(EmployeePpeSize(employee_id=db_employee.id, size_group_id=size_data.size_group_id, size_value=size_data.size_value))

    try:
        await db.commit()
    except StaleDataError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Конфликт версий") from exc
    except IntegrityError as exc:
        # Страховка на случай гонки: параллельный запрос успел вставить тот же
        # размер или занять номер карточки между проверкой и commit
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Не удалось сохранить сотрудника: номер личной карточки или "
                "размер по одной из групп уже заняты"
            ),
        ) from exc

    await broadcast(employee_id, {"event": "employee_updated", "employee_id": employee_id})

    employee = ensure_found(
        await get_employee_with_relations(db, employee_id), "Сотрудник не найден"
    )
    return employee


@router.delete("/{employee_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_employee(
    employee_id: int, 
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user)
):
    result = await db.execute(
        select(Employee)
        .where(Employee.id == employee_id)
        .options(selectinload(Employee.photo))
    )
    db_employee = ensure_found(result.scalar_one_or_none(), "Сотрудник не найден")

    allowed = await get_allowed_department_ids(db, current_user)
    if allowed and db_employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")

    # Имя файла запоминаем до удаления: FK с CASCADE уберёт запись
    # employee_photos, но файл на томе сам не исчезнет
    photo_filename = db_employee.photo.filename if db_employee.photo else None

    try:
        await db.delete(db_employee)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления") from exc

    if photo_filename:
        delete_photo_file(photo_filename)

    await broadcast(0, {"event": "employee_updated", "employee_id": employee_id})


# --- Фото сотрудника -------------------------------------------------------
# Файл лежит в каталоге PHOTO_DIR (том данных), в БД — только метаданные.
# Отдача идёт через API, а не из /static: фото — персональные данные, и
# отдавать его без проверки прав нельзя. Кэш — приватный, ETag по содержимому.


async def get_employee_for_photo(db: AsyncSession, employee_id: int) -> Employee:
    """Сотрудник с фото — без выдач и размеров: здесь они не нужны."""
    result = await db.execute(
        select(Employee)
        .where(Employee.id == employee_id)
        .options(selectinload(Employee.photo))
    )
    return ensure_found(result.scalar_one_or_none(), "Сотрудник не найден")


async def ensure_employee_access(
    db: AsyncSession, employee: Employee, user: User
) -> None:
    """Та же проверка подразделений, что у карточки сотрудника."""
    allowed = await get_allowed_department_ids(db, user)
    if allowed and employee.department_id not in allowed:
        raise HTTPException(status_code=403, detail="Доступ запрещен")


@router.get(
    "/{employee_id}/photo",
    response_class=Response,
    responses={200: {"content": {"image/jpeg": {}}}, 304: {"description": "Не изменилось"}},
)
async def get_employee_photo(
    employee_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Фото сотрудника. Повторный запрос с тем же ETag — 304."""
    employee = await get_employee_for_photo(db, employee_id)
    await ensure_employee_access(db, employee, current_user)

    if employee.photo is None:
        raise HTTPException(status_code=404, detail="У сотрудника нет фото")

    path = photo_path(employee.photo.filename)
    if not path.exists():
        # Файл мог не переехать вместе с базой: том с фото подключается отдельно
        raise HTTPException(
            status_code=404,
            detail="Файл фото не найден: проверьте, что том с фото подключён",
        )

    etag = f'"{employee.photo.sha256}"'
    headers = {"ETag": etag, "Cache-Control": "private, max-age=300"}
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=headers)

    return FileResponse(path, media_type=employee.photo.mime_type, headers=headers)


@router.post("/{employee_id}/photo", response_model=EmployeePhotoMeta)
async def upload_employee_photo(
    employee_id: int,
    file: UploadFile = File(..., description="JPEG, PNG или WebP"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Загрузить (или заменить) фото. Файл приводится к портрету 400×500 в JPEG."""
    employee = await get_employee_for_photo(db, employee_id)
    await ensure_employee_access(db, employee, current_user)

    filename, mime, size, sha256 = await store_employee_photo(file)
    old_filename = employee.photo.filename if employee.photo else None

    if employee.photo is None:
        photo = EmployeePhoto(
            employee_id=employee_id,
            filename=filename,
            mime_type=mime,
            size_bytes=size,
            sha256=sha256,
        )
        db.add(photo)
    else:
        photo = employee.photo
        photo.filename = filename
        photo.mime_type = mime
        photo.size_bytes = size
        photo.sha256 = sha256
        photo.uploaded_at = datetime.now(UTC)

    await commit_or_400(db, "Не удалось сохранить фото")
    await db.refresh(photo)

    # Старый файл удаляем только после успешной записи метаданных
    if old_filename:
        delete_photo_file(old_filename)

    await broadcast(0, {"event": "employee_updated", "employee_id": employee_id})
    return photo


@router.delete("/{employee_id}/photo", status_code=status.HTTP_204_NO_CONTENT)
async def delete_employee_photo(
    employee_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_active_user),
):
    """Удалить фото. Идемпотентно: если фото нет — тоже 204."""
    employee = await get_employee_for_photo(db, employee_id)
    await ensure_employee_access(db, employee, current_user)

    if employee.photo is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    filename = employee.photo.filename
    await db.delete(employee.photo)
    await commit_or_400(db, "Не удалось удалить фото")
    delete_photo_file(filename)

    await broadcast(0, {"event": "employee_updated", "employee_id": employee_id})
    return Response(status_code=status.HTTP_204_NO_CONTENT)

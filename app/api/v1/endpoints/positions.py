from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api import pagination
from app.db.session import get_db
from app.models.department import Department
from app.models.position import Position
from app.schemas.position import PositionCreate, PositionRead, PositionUpdate
from app.utils.broadcast import broadcast

router = APIRouter(prefix="/positions", tags=["Справочник: Должности"])

@router.post("/", response_model=PositionRead, status_code=status.HTTP_201_CREATED)
async def create_position(pos_in: PositionCreate, db: AsyncSession = Depends(get_db)):
    cat_result = await db.execute(select(Department).where(Department.id == pos_in.department_id))
    if not cat_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Подразделение не найдено")

    # Две одинаковые должности в одном подразделении — это ошибка ввода,
    # а не две разные сущности: нормы на них пришлось бы задавать дважды.
    dup = await db.execute(
        select(Position.id).where(
            Position.department_id == pos_in.department_id,
            Position.name == pos_in.name,
        )
    )
    if dup.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="В этом подразделении уже есть должность с таким названием",
        )

    db_pos = Position(**pos_in.model_dump())
    db.add(db_pos)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=400,
            detail="В этом подразделении уже есть должность с таким названием",
        ) from exc
    await db.refresh(db_pos)
    result = await db.execute(select(Position).where(Position.id == db_pos.id).options(selectinload(Position.department)))
    return result.scalar_one()

@router.get("/", response_model=None)
async def get_positions(
    db: AsyncSession = Depends(get_db),
    page: int = Query(1, ge=1, description="Номер страницы"),
    page_size: int = Query(
        pagination.DEFAULT_PAGE_SIZE, ge=1, le=pagination.MAX_PAGE_SIZE
    ),
    search: str | None = Query(None, description="Поиск по названию должности"),
    department_id: int | None = Query(None, description="Фильтр по подразделению"),
    paginated: bool = Query(False, description="Вернуть страницу с метаданными"),
):
    """Должности. Без paginated — полный массив для выпадающих списков."""
    conditions = []
    if search:
        pattern = f"%{search.strip().lower()}%"
        conditions.append(func.lower(Position.name).like(pattern))
    if department_id is not None:
        conditions.append(Position.department_id == department_id)

    base = select(Position).where(*conditions) if conditions else select(Position)

    if not paginated:
        result = await db.execute(
            base.options(selectinload(Position.department)).order_by(Position.name)
        )
        return result.scalars().all()

    total = (
        await db.execute(select(func.count()).select_from(base.subquery()))
    ).scalar_one()

    params = pagination.normalize(page, page_size)
    result = await db.execute(
        base.options(selectinload(Position.department))
        .order_by(Position.name, Position.id)
        .offset(params.offset)
        .limit(params.page_size)
    )
    items = result.scalars().all()

    return pagination.Page.build(
        [PositionRead.model_validate(item) for item in items],
        total=total,
        page=params.page,
        page_size=params.page_size,
    )

@router.get("/{pos_id}", response_model=PositionRead)
async def get_position(pos_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id).options(selectinload(Position.department)))
    pos = result.scalar_one_or_none()
    if not pos:
        raise HTTPException(status_code=404, detail="Не найдено")
    return pos

@router.put("/{pos_id}", response_model=PositionRead)
async def update_position(pos_id: int, pos_in: PositionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id))
    db_pos = result.scalar_one_or_none()
    if not db_pos:
        raise HTTPException(status_code=404, detail="Не найдено")
    if db_pos.version != pos_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    # Без проверки несуществующий department_id ронял бы commit в 500 (FK)
    if pos_in.department_id is not None:
        dept_res = await db.execute(select(Department).where(Department.id == pos_in.department_id))
        if not dept_res.scalar_one_or_none():
            raise HTTPException(status_code=404, detail="Подразделение не найдено")

    # Переименование в уже существующую должность того же подразделения
    target_name = pos_in.name if pos_in.name is not None else db_pos.name
    target_dept = pos_in.department_id if pos_in.department_id is not None else db_pos.department_id
    dup = await db.execute(
        select(Position.id).where(
            Position.department_id == target_dept,
            Position.name == target_name,
            Position.id != pos_id,
        )
    )
    if dup.scalar_one_or_none():
        raise HTTPException(
            status_code=400,
            detail="В этом подразделении уже есть должность с таким названием",
        )

    for field, value in pos_in.model_dump(exclude_unset=True, exclude={"version"}).items():
        setattr(db_pos, field, value)
    db_pos.version += 1
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=400,
            detail="В этом подразделении уже есть должность с таким названием",
        ) from exc
    await broadcast(0, {"event": "position_updated", "id": pos_id})
    result = await db.execute(select(Position).where(Position.id == pos_id).options(selectinload(Position.department)))
    return result.scalar_one()

@router.delete("/{pos_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_position(pos_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Position).where(Position.id == pos_id))
    db_pos = result.scalar_one_or_none()
    if not db_pos:
        raise HTTPException(status_code=404, detail="Не найдено")
    try:
        await db.delete(db_pos)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Нельзя удалить, есть привязанные сотрудники") from exc

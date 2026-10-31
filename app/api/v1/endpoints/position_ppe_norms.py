from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.exc import IntegrityError
from app.api import pagination
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.position import Position
from app.models.ppe_item import PpeItem
from app.models.ppe_function import PpeFunction
from app.models.ppe_size_group import PpeSizeGroup
from app.schemas.position_ppe_norm import PositionPpeNormCreate, PositionPpeNormRead, PositionPpeNormUpdate

router = APIRouter(prefix="/position_ppe_norms", tags=["Нормы выдачи СИЗ"])


def norm_options():
    return [
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.function),
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.size_group),
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.unit),
        selectinload(PositionPpeNorm.position).selectinload(Position.department)
    ]


async def get_norm_with_relations(db: AsyncSession, norm_id: int) -> PositionPpeNorm | None:
    result = await db.execute(
        select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id).options(*norm_options())
    )
    # scalar_one() падал бы NoResultFound (500) вместо 404
    return result.scalar_one_or_none()


@router.post("/", response_model=PositionPpeNormRead, status_code=status.HTTP_201_CREATED)
async def create_norm(norm_in: PositionPpeNormCreate, db: AsyncSession = Depends(get_db)):
    pos_res = await db.execute(select(Position).where(Position.id == norm_in.position_id))
    if not pos_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Должность не найдена")
        
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == norm_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    db_norm = PositionPpeNorm(**norm_in.model_dump())
    db.add(db_norm)
    
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400, 
            detail="Для этой должности норма на данное СИЗ уже существует."
        )
        
    norm = await get_norm_with_relations(db, db_norm.id)
    if norm is None:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    return norm


@router.get("/", response_model=None)
async def get_norms(
    db: AsyncSession = Depends(get_db),
    page: int = Query(1, ge=1, description="Номер страницы"),
    page_size: int = Query(
        pagination.DEFAULT_PAGE_SIZE, ge=1, le=pagination.MAX_PAGE_SIZE
    ),
    search: str | None = Query(None, description="Поиск по должности или СИЗ"),
    position_id: int | None = Query(None, description="Фильтр по должности"),
    department_id: int | None = Query(None, description="Фильтр по подразделению"),
    paginated: bool = Query(False, description="Вернуть страницу с метаданными"),
):
    """Нормы выдачи.

    Поиск идёт по названию должности и по наименованию СИЗ — это требует
    соединения с таблицами positions и ppe_items, поэтому фильтрация
    перенесена из браузера в SQL.
    """
    query = select(PositionPpeNorm)

    if position_id is not None:
        query = query.where(PositionPpeNorm.position_id == position_id)

    if department_id is not None:
        query = query.join(Position, PositionPpeNorm.position_id == Position.id).where(
            Position.department_id == department_id
        )

    if search:
        pattern = f"%{search.strip().lower()}%"
        query = query.join(
            Position, PositionPpeNorm.position_id == Position.id
        ).join(
            PpeItem, PositionPpeNorm.ppe_item_id == PpeItem.id
        ).where(
            or_(
                func.lower(Position.name).like(pattern),
                func.lower(PpeItem.name).like(pattern),
            )
        )

    if not paginated:
        result = await db.execute(query.options(*norm_options()))
        return result.scalars().all()

    total = (
        await db.execute(select(func.count()).select_from(query.subquery()))
    ).scalar_one()

    params = pagination.normalize(page, page_size)
    stmt = (
        query.options(*norm_options())
        .order_by(PositionPpeNorm.id)
        .offset(params.offset)
        .limit(params.page_size)
    )
    result = await db.execute(stmt)
    items = result.scalars().all()

    return pagination.Page.build(
        [PositionPpeNormRead.model_validate(item) for item in items],
        total=total,
        page=params.page,
        page_size=params.page_size,
    )


@router.get("/{norm_id}", response_model=PositionPpeNormRead)
async def get_norm(norm_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id).options(*norm_options()))
    norm = result.scalar_one_or_none()
    if not norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    return norm


@router.put("/{norm_id}", response_model=PositionPpeNormRead)
async def update_norm(norm_id: int, norm_in: PositionPpeNormUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    if db_norm.version != norm_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
    
    update_data = norm_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_norm, field, value)
    db_norm.version += 1
    
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Такая норма уже существует")
    
    try:
        await manager.broadcast_to_employee(0, {"event": "norm_updated", "id": norm_id})
    except: pass

    norm = await get_norm_with_relations(db, norm_id)
    if norm is None:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    return norm


class BulkDeleteRequest(BaseModel):
    ids: list[int]


@router.post("/bulk-delete")
async def bulk_delete_norms(data: BulkDeleteRequest, db: AsyncSession = Depends(get_db)):
    """Удаляет выбранные нормы одним запросом.

    Раньше клиент слал N отдельных DELETE: падение на середине оставляло часть
    норм удалёнными, а часть — нет, и повторить операцию было нечем.
    """
    if not data.ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одной нормы")

    result = await db.execute(select(PositionPpeNorm.id).where(PositionPpeNorm.id.in_(data.ids)))
    found = set(result.scalars().all())
    if not found:
        raise HTTPException(status_code=404, detail="Нормы не найдены")

    try:
        await db.execute(delete(PositionPpeNorm).where(PositionPpeNorm.id.in_(found)))
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")

    try:
        await manager.broadcast_to_employee(0, {"event": "norm_updated", "id": 0})
    except Exception:
        pass

    missing = sorted(set(data.ids) - found)
    return {
        "message": f"Удалено норм: {len(found)}",
        "deleted": len(found),
        "missing": missing,
    }


@router.delete("/{norm_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_norm(norm_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Норма не найдена")
    try:
        await db.delete(db_norm)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")

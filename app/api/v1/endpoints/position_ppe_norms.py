from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api import pagination
from app.api.db import commit_or_400
from app.api.versioning import ensure_version
from app.db.session import get_db
from app.models.position import Position
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.ppe_item import PpeItem
from app.models.typical_norm import TypicalNorm
from app.schemas.position_ppe_norm import (
    PositionPpeNormCreate,
    PositionPpeNormRead,
    PositionPpeNormUpdate,
)
from app.utils.broadcast import broadcast

router = APIRouter(prefix="/position_ppe_norms", tags=["Нормы выдачи СИЗ"])


def norm_options():
    return [
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.function),
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.size_group),
        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.unit),
        selectinload(PositionPpeNorm.typical_norm),
        selectinload(PositionPpeNorm.position).selectinload(Position.department)
    ]


async def get_norm_with_relations(db: AsyncSession, norm_id: int) -> PositionPpeNorm | None:
    result = await db.execute(
        select(PositionPpeNorm).where(PositionPpeNorm.id == norm_id).options(*norm_options())
    )
    # scalar_one() падал бы NoResultFound (500) вместо 404
    return result.scalar_one_or_none()


async def ensure_typical_norm_exists(
    db: AsyncSession, typical_norm_id: int | None
) -> None:
    """Пункт норм выбирается из справочника — проверяем, что он ещё существует.

    Без этого удалённый в другой вкладке пункт давал бы IntegrityError и
    непонятное «не удалось сохранить».
    """
    if typical_norm_id is None:
        return

    result = await db.execute(select(TypicalNorm.id).where(TypicalNorm.id == typical_norm_id))
    if result.scalar_one_or_none() is None:
        raise HTTPException(status_code=404, detail="Пункт типовых норм не найден")


class CopyNormsRequest(BaseModel):
    """Копирование норм с одной должности на другие."""

    source_position_id: int = Field(..., description="Откуда копировать")
    target_position_ids: list[int] = Field(..., description="Куда копировать")


@router.post("/", response_model=PositionPpeNormRead, status_code=status.HTTP_201_CREATED)
async def create_norm(norm_in: PositionPpeNormCreate, db: AsyncSession = Depends(get_db)):
    pos_res = await db.execute(select(Position).where(Position.id == norm_in.position_id))
    if not pos_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Должность не найдена")
        
    item_res = await db.execute(select(PpeItem).where(PpeItem.id == norm_in.ppe_item_id))
    if not item_res.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Наименование СИЗ не найдено")

    await ensure_typical_norm_exists(db, norm_in.typical_norm_id)

    db_norm = PositionPpeNorm(**norm_in.model_dump())
    db.add(db_norm)
    
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=400,
            detail=(
                "Не удалось сохранить норму: должность или наименование СИЗ"
                " были изменены. Обновите страницу и повторите."
            ),
        ) from exc
        
    norm = await get_norm_with_relations(db, db_norm.id)
    if norm is None:
        raise HTTPException(status_code=404, detail="Норма не найдена")

    # Матрица норм другой должности в соседней вкладке должна обновиться
    await broadcast(0, {"event": "norm_updated", "id": db_norm.id})
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


def norm_signature(position_id: int, norm: Any) -> tuple[int, int, str, str, str]:
    """Ключ нормы для сравнения при копировании.

    Пары «должность + СИЗ» недостаточно: после миграции a9f3c06b2d18 у неё
    может быть основное наименование и до четырёх альтернатив, которые
    отличаются сроком носки и количеством. Сравнение по одной паре принимало
    бы альтернативы за дубли и не копировало их.

    Подходит и ORM-объекту, и строке select-запроса: у обоих есть одноимённые
    атрибуты.
    """
    return (
        position_id,
        norm.ppe_item_id,
        (norm.wear_period_value or "").strip(),
        (norm.wear_period_unit or "").strip(),
        (norm.quantity or "").strip(),
    )


@router.post("/copy")
async def copy_norms(data: CopyNormsRequest, db: AsyncSession = Depends(get_db)):
    """Копирует нормы с одной должности на другие.

    Часто у нескольких должностей нормы совпадают — проще скопировать набор,
    чем заводить каждую строку заново.

    Копируются все нормы источника, включая альтернативы: у пары
    «должность + СИЗ» их может быть несколько. Существующие нормы получателей
    не изменяются, а повторный запуск безопасен — пропускается только точное
    совпадение по СИЗ, сроку носки и количеству.
    """
    if not data.target_position_ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одной должности-получателя")

    if data.source_position_id in data.target_position_ids:
        raise HTTPException(
            status_code=400,
            detail="Должность-источник не может быть получателем",
        )

    source_res = await db.execute(
        select(PositionPpeNorm)
        .where(PositionPpeNorm.position_id == data.source_position_id)
        # Явный порядок: без него Postgres вправе вернуть нормы в другом
        # порядке, и id созданных копий менялись бы от запуска к запуску
        .order_by(PositionPpeNorm.id)
    )
    source_norms = source_res.scalars().all()
    if not source_norms:
        raise HTTPException(
            status_code=400,
            detail="У выбранной должности нет норм — копировать нечего",
        )

    # Проверяем, что все получатели существуют
    targets_res = await db.execute(
        select(Position.id).where(Position.id.in_(data.target_position_ids))
    )
    found_targets = set(targets_res.scalars().all())
    missing_targets = sorted(set(data.target_position_ids) - found_targets)
    if not found_targets:
        raise HTTPException(status_code=404, detail="Должности-получатели не найдены")

    # Что уже есть у получателей: полный набор значимых полей, а не только
    # пара «должность + СИЗ». Пара не уникальна — у неё есть альтернативы,
    # и сравнение по паре принимало бы их за дубли.
    existing_res = await db.execute(
        select(
            PositionPpeNorm.position_id,
            PositionPpeNorm.ppe_item_id,
            PositionPpeNorm.wear_period_value,
            PositionPpeNorm.wear_period_unit,
            PositionPpeNorm.quantity,
        ).where(PositionPpeNorm.position_id.in_(found_targets))
    )
    existing = {norm_signature(row.position_id, row) for row in existing_res.all()}

    created = 0
    skipped = 0

    # sorted(): порядок обхода set случаен, а от него зависят id созданных
    # норм — без явного порядка результат повторного запуска отличался бы
    for position_id in sorted(found_targets):
        for norm in source_norms:
            key = norm_signature(position_id, norm)
            if key in existing:
                skipped += 1
                continue

            db.add(
                PositionPpeNorm(
                    position_id=position_id,
                    ppe_item_id=norm.ppe_item_id,
                    # Пункт норм копируем вместе с нормой: у должностей из
                    # одного приложения основание выдачи то же самое
                    typical_norm_id=norm.typical_norm_id,
                    wear_period_value=norm.wear_period_value,
                    wear_period_unit=norm.wear_period_unit,
                    quantity=norm.quantity,
                )
            )
            existing.add(key)
            created += 1

    await commit_or_400(db, "Ошибка копирования норм")

    await broadcast(0, {"event": "norm_updated", "id": 0})

    return {
        "message": f"Скопировано норм: {created}, пропущено: {skipped}",
        "created": created,
        "skipped": skipped,
        "missing_targets": missing_targets,
    }


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
    ensure_version(db_norm.version, norm_in.version)
    
    update_data = norm_in.model_dump(exclude_unset=True, exclude={"version"})
    if "typical_norm_id" in update_data:
        await ensure_typical_norm_exists(db, update_data["typical_norm_id"])

    for field, value in update_data.items():
        setattr(db_norm, field, value)
    db_norm.version += 1
    
    await commit_or_400(db, "Не удалось сохранить изменения нормы. Обновите страницу и повторите.")
    
    await broadcast(0, {"event": "norm_updated", "id": norm_id})

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
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления") from exc

    await broadcast(0, {"event": "norm_updated", "id": 0})

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
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления") from exc

    await broadcast(0, {"event": "norm_updated", "id": norm_id})

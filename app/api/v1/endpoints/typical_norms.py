import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import exists, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.typical_norm import TypicalNorm
from app.schemas.typical_norm import (
    TypicalNormCreate,
    TypicalNormRead,
    TypicalNormUpdate,
)

router = APIRouter(prefix="/typical_norms", tags=["Справочник: Типовые нормы"])


async def ensure_clause_free(
    db: AsyncSession, clause: str, norm_id: int | None = None
) -> None:
    """Пункт нормы — это ссылка из карточки, значит он должен быть один."""
    query = select(TypicalNorm).where(TypicalNorm.clause == clause)
    if norm_id is not None:
        query = query.where(TypicalNorm.id != norm_id)

    if (await db.execute(query)).scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Пункт «{clause}» уже есть в справочнике",
        )


@router.post("/", response_model=TypicalNormRead, status_code=status.HTTP_201_CREATED)
async def create_typical_norm(
    norm_in: TypicalNormCreate, db: AsyncSession = Depends(get_db)
):
    await ensure_clause_free(db, norm_in.clause)

    db_norm = TypicalNorm(**norm_in.model_dump())
    db.add(db_norm)
    try:
        await db.commit()
    except IntegrityError as exc:
        # Страховка на гонку: параллельный запрос успел вставить тот же пункт
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Пункт «{norm_in.clause}» уже есть в справочнике",
        ) from exc

    await db.refresh(db_norm)
    return db_norm


@router.get("/", response_model=list[TypicalNormRead])
async def get_typical_norms(
    search: str | None = Query(None, description="Поиск по пункту или описанию"),
    db: AsyncSession = Depends(get_db),
):
    query = select(TypicalNorm)
    if search:
        pattern = f"%{search.strip().lower()}%"
        query = query.where(
            sa.or_(
                sa.func.lower(TypicalNorm.clause).like(pattern),
                sa.func.lower(TypicalNorm.description).like(pattern),
            )
        )

    # Порядок — по номеру пункта, а не по строке: иначе «п. 12» встало бы
    # перед «п. 4». Число берём первым совпадением в строке: пункт может быть
    # записан как «п. 4», «4.1» или «Приложение №1, п. 12»
    numeric = sa.cast(
        sa.func.nullif(sa.func.substring(TypicalNorm.clause, r"[0-9]+"), ""),
        sa.Integer,
    )
    result = await db.execute(query.order_by(numeric.nulls_last(), TypicalNorm.clause))
    return result.scalars().all()


@router.put("/{norm_id}", response_model=TypicalNormRead)
async def update_typical_norm(
    norm_id: int, norm_in: TypicalNormUpdate, db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(TypicalNorm).where(TypicalNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Пункт норм не найден")

    if db_norm.version != norm_in.version:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Данные устарели")

    update_data = norm_in.model_dump(exclude_unset=True, exclude={"version"})
    if "clause" in update_data:
        await ensure_clause_free(db, update_data["clause"], norm_id)

    for field, value in update_data.items():
        setattr(db_norm, field, value)
    db_norm.version += 1

    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пункт с таким номером уже есть в справочнике",
        ) from exc

    await db.refresh(db_norm)
    return db_norm


@router.delete("/{norm_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_typical_norm(norm_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(TypicalNorm).where(TypicalNorm.id == norm_id))
    db_norm = result.scalar_one_or_none()
    if not db_norm:
        raise HTTPException(status_code=404, detail="Пункт норм не найден")

    # Ссылку из норм не обнуляем молча: пункт — основание выдачи, в карточке
    # он должен остаться. На уровне БД то же самое делает ON DELETE RESTRICT
    in_use = await db.execute(
        select(exists().where(PositionPpeNorm.typical_norm_id == norm_id))
    )
    if in_use.scalar():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пункт указан в нормах выдачи — сначала уберите его оттуда",
        )

    try:
        await db.delete(db_norm)
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Пункт указан в нормах выдачи — сначала уберите его оттуда",
        ) from exc

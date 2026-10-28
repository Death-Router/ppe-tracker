from fastapi import APIRouter, Depends, HTTPException, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.exc import StaleDataError

from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.ppe_category import PpeCategory
from app.schemas.ppe_category import (
    PpeCategoryCreate,
    PpeCategoryRead,
    PpeCategoryUpdate,
)

router = APIRouter(prefix="/ppe_categories", tags=["Справочник: Категории СИЗ"])


@router.post("/", response_model=PpeCategoryRead, status_code=status.HTTP_201_CREATED)
async def create_category(
    category_in: PpeCategoryCreate, db: AsyncSession = Depends(get_db)
):
    result = await db.execute(
        select(PpeCategory).where(PpeCategory.name == category_in.name)
    )
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=400, detail="Категория с таким названием уже существует"
        )

    db_category = PpeCategory(**category_in.model_dump())
    db.add(db_category)
    await db.commit()
    await db.refresh(db_category)
    return db_category


@router.get("/", response_model=list[PpeCategoryRead])
async def get_categories(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeCategory))
    return result.scalars().all()


@router.get("/{category_id}", response_model=PpeCategoryRead)
async def get_category(category_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeCategory).where(PpeCategory.id == category_id))
    category = result.scalar_one_or_none()
    if not category:
        raise HTTPException(status_code=404, detail="Категория не найдена")
    return category


@router.put("/{category_id}", response_model=PpeCategoryRead)
async def update_category(
    category_id: int,
    category_in: PpeCategoryUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(PpeCategory).where(PpeCategory.id == category_id))
    db_category = result.scalar_one_or_none()

    if not db_category:
        raise HTTPException(status_code=404, detail="Категория не найдена")

    if db_category.version != category_in.version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Данные были изменены другим пользователем. Обновите страницу.",
        )

    update_data = category_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        if value is not None:
            setattr(db_category, field, value)

    db_category.version += 1

    try:
        await db.commit()
    except StaleDataError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Конфликт версий при сохранении. Данные были изменены.",
        )

    try:
        await manager.broadcast_to_employee(
            0, {"event": "category_updated", "category_id": category_id}
        )
    except (WebSocketDisconnect, RuntimeError) as e:
        print(f"Ошибка WS: {e}")

    return db_category


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(category_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeCategory).where(PpeCategory.id == category_id))
    db_category = result.scalar_one_or_none()

    if not db_category:
        raise HTTPException(status_code=404, detail="Категория не найдена")

    try:
        await db.delete(db_category)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Невозможно удалить категорию, так как к ней привязаны наименования СИЗ.",
        )

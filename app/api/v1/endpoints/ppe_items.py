from fastapi import APIRouter, Depends, HTTPException, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.exc import StaleDataError

from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.schemas.ppe_item import PpeItemCreate, PpeItemRead, PpeItemUpdate

router = APIRouter(prefix="/ppe_items", tags=["Справочник: Наименования СИЗ"])


@router.post("/", response_model=PpeItemRead, status_code=status.HTTP_201_CREATED)
async def create_item(item: PpeItemCreate, db: AsyncSession = Depends(get_db)):
    # 1. Проверяем, существует ли категория, к которой мы привязываем СИЗ
    category_result = await db.execute(
        select(PpeCategory).where(PpeCategory.id == item.category_id)
    )
    if not category_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Категория с ID {item.category_id} не найдена",
        )

    # 2. Проверяем, нет ли уже такого наименования в этой категории
    item_result = await db.execute(
        select(PpeItem).where(
            PpeItem.name == item.name, PpeItem.category_id == item.category_id
        )
    )
    if item_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Такое наименование в этой категории уже существует",
        )

    # 3. Создаем запись
    db_item = PpeItem(name=item.name, category_id=item.category_id)
    db.add(db_item)
    await db.commit()

    # 4. Загружаем объект заново, чтобы подтянуть связанную категорию для ответа
    await db.refresh(db_item)
    result_with_category = await db.execute(
        select(PpeItem)
        .where(PpeItem.id == db_item.id)
        .options(selectinload(PpeItem.category))
    )
    return result_with_category.scalar_one()


@router.get("/", response_model=list[PpeItemRead])
async def get_items(db: AsyncSession = Depends(get_db)):
    # Используем selectinload, чтобы одним запросом подтянуть категории для всех СИЗ
    result = await db.execute(select(PpeItem).options(selectinload(PpeItem.category)))
    return result.scalars().all()


@router.get("/{item_id}", response_model=PpeItemRead)
async def get_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(PpeItem)
        .where(PpeItem.id == item_id)
        .options(selectinload(PpeItem.category))
    )
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")
    return item


@router.put("/{item_id}", response_model=PpeItemRead)
async def update_item(
    item_id: int,
    item_in: PpeItemUpdate,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()

    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    # 1. Проверка оптимистичной блокировки
    if db_item.version != item_in.version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Данные были изменены другим пользователем. Обновите страницу.",
        )

    # 2. Если меняется категория — проверяем, существует ли она
    if item_in.category_id is not None and item_in.category_id != db_item.category_id:
        cat_result = await db.execute(
            select(PpeCategory).where(PpeCategory.id == item_in.category_id)
        )
        if not cat_result.scalar_one_or_none():
            raise HTTPException(
                status_code=404,
                detail=f"Категория с ID {item_in.category_id} не найдена",
            )

    update_data = item_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_item, field, value)

    db_item.version += 1

    try:
        await db.commit()
    except StaleDataError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Конфликт версий при сохранении.",
        )

    # 3. Отправка WebSocket
    try:
        await manager.broadcast_to_employee(
            0, {"event": "item_updated", "item_id": item_id}
        )
    except (WebSocketDisconnect, RuntimeError) as e:
        print(f"Ошибка WS: {e}")

    # 4. Загружаем обновленный объект с категорией
    result = await db.execute(
        select(PpeItem)
        .where(PpeItem.id == item_id)
        .options(selectinload(PpeItem.category))
    )
    return result.scalar_one()


@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()

    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    try:
        await db.delete(db_item)
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400,
            detail="Невозможно удалить наименование, так как оно используется в размерах сотрудников.",
        )

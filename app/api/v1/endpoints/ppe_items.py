from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, exists, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.api.v1.endpoints.ws import manager
from app.db.session import get_db
from app.models.ppe_item import PpeItem
from app.models.ppe_function import PpeFunction
from app.models.ppe_size_group import PpeSizeGroup
from app.models.unit import Unit
from app.models.position_ppe_norm import PositionPpeNorm
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.schemas.ppe_item import PpeItemCreate, PpeItemRead, PpeItemUpdate

router = APIRouter(prefix="/ppe_items", tags=["Справочник: Наименования СИЗ"])

def item_options():
    return [
        selectinload(PpeItem.function),
        selectinload(PpeItem.size_group),
        selectinload(PpeItem.unit)
    ]

@router.post("/", response_model=PpeItemRead, status_code=status.HTTP_201_CREATED)
async def create_item(item_in: PpeItemCreate, db: AsyncSession = Depends(get_db)):
    db_item = PpeItem(**item_in.model_dump())
    db.add(db_item)
    await db.commit()
    await db.refresh(db_item)
    
    result = await db.execute(select(PpeItem).where(PpeItem.id == db_item.id).options(*item_options()))
    return result.scalar_one()

@router.get("/", response_model=list[PpeItemRead])
async def get_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).options(*item_options()))
    return result.scalars().all()

@router.get("/{item_id}", response_model=PpeItemRead)
async def get_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id).options(*item_options()))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")
    return item

@router.put("/{item_id}", response_model=PpeItemRead)
async def update_item(item_id: int, item_in: PpeItemUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    if db_item.version != item_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")

    update_data = item_in.model_dump(exclude_unset=True, exclude={"version"})
    for field, value in update_data.items():
        setattr(db_item, field, value)
    db_item.version += 1
    await db.commit()

    try:
        await manager.broadcast_to_employee(0, {"event": "item_updated", "item_id": item_id})
    except Exception:
        pass

    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id).options(*item_options()))
    return result.scalar_one()

@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_item(item_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(PpeItem).where(PpeItem.id == item_id))
    db_item = result.scalar_one_or_none()
    if not db_item:
        raise HTTPException(status_code=404, detail="Наименование не найдено")

    # Проверяем, есть ли нормы на это СИЗ
    norm_exists = await db.execute(
        select(exists().where(PositionPpeNorm.ppe_item_id == item_id))
    )
    if norm_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Нельзя удалить СИЗ, так как оно используется в нормах выдачи"
        )

    # Проверяем, есть ли выдачи этого СИЗ
    issue_exists = await db.execute(
        select(exists().where(EmployeePpeIssue.ppe_item_id == item_id))
    )
    if issue_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Нельзя удалить СИЗ, так как оно было выдано сотрудникам"
        )

    try:
        await db.delete(db_item)
        await db.commit()
    except Exception:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Ошибка удаления")


# --- Массовые операции ---
from pydantic import BaseModel
from typing import List

class BulkUpdateRequest(BaseModel):
    ids: List[int]
    function_id: int | None = None
    size_group_id: int | None = None
    unit_id: int | None = None

@router.patch("/bulk")
async def bulk_update_items(
    data: BulkUpdateRequest, 
    db: AsyncSession = Depends(get_db)
):
    """Массовое обновление функций, размерных групп или единиц измерения для СИЗ."""
    if not data.ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одного СИЗ")

    result = await db.execute(select(PpeItem).where(PpeItem.id.in_(data.ids)))
    items = result.scalars().all()
    
    if not items:
        raise HTTPException(status_code=404, detail="СИЗ не найдены")

    for item in items:
        if data.function_id is not None:
            item.function_id = data.function_id if data.function_id != 0 else None
        if data.size_group_id is not None:
            item.size_group_id = data.size_group_id if data.size_group_id != 0 else None
        if data.unit_id is not None:
            item.unit_id = data.unit_id if data.unit_id != 0 else None
        item.version += 1

    await db.commit()
    return {"message": f"Обновлено {len(items)} записей"}


class BulkDeleteRequest(BaseModel):
    ids: List[int]

@router.post("/bulk-delete")
async def bulk_delete_items(
    data: BulkDeleteRequest, 
    db: AsyncSession = Depends(get_db)
):
    """Массовое удаление СИЗ с проверкой использования в нормах и выдачах."""
    if not data.ids:
        raise HTTPException(status_code=400, detail="Не выбрано ни одного СИЗ")

    # Проверяем, есть ли нормы или выдачи для этих СИЗ
    norm_exists = await db.execute(
        select(exists().where(PositionPpeNorm.ppe_item_id.in_(data.ids)))
    )
    if norm_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Некоторые СИЗ используются в нормах выдачи. Удаление запрещено."
        )

    issue_exists = await db.execute(
        select(exists().where(EmployeePpeIssue.ppe_item_id.in_(data.ids)))
    )
    if issue_exists.scalar():
        raise HTTPException(
            status_code=400, 
            detail="Некоторые СИЗ были выданы сотрудникам. Удаление запрещено."
        )

    await db.execute(delete(PpeItem).where(PpeItem.id.in_(data.ids)))
    await db.commit()
    return {"message": f"Удалено {len(data.ids)} записей"}

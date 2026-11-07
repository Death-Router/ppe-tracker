"""Транзакции: commit с понятной ошибкой вместо голого 500.

Нарушение ограничения БД (уникальность, внешний ключ) сейчас ловится в
каждом endpoint'е одинаковым блоком:

    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=400, detail="...") from exc

Текст ошибки остаётся у вызывающего — он у каждой сущности свой, — а обработка
одна: откатить транзакцию и ответить 400, а не 500.
"""
from fastapi import HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession


async def commit_or_400(db: AsyncSession, detail: str) -> None:
    """Коммитит; при нарушении ограничения БД откатывает и отвечает 400."""
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=detail,
        ) from exc

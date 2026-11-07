"""Транзакции и загрузка объектов: общие операции вместо копий в endpoint'ах.

Здесь два хелпера:

- `commit_or_400` — commit с rollback и 400 при нарушении ограничения БД
  (было 12 одинаковых блоков);
- `ensure_found` / `fetch_or_404` — 404 «не найдено» с текстом сущности
  (было 36 копий `if not obj: raise HTTPException(404, ...)`).
"""
from collections.abc import Sequence
from typing import Any, TypeVar

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

T = TypeVar("T")


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


def ensure_found(obj: T | None, detail: str) -> T:
    """Возвращает объект или отвечает 404 с текстом сущности.

    Для выборок не по id (по имени, по паре полей) и для `db.get()`:
    проверка одна, а текст остаётся у сущности.
    """
    if obj is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)
    return obj


def ensure_non_empty(items: Sequence[T], detail: str) -> Sequence[T]:
    """То же для выборки: пустой список — это 404, а не пустой ответ.

    Отличается от `ensure_found` тем, что `[]` (а не `None`) тоже считается
    «ничего не найдено»: так ведут себя массовые операции и списки по фильтру.
    """
    if not items:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=detail)
    return items


async def fetch_or_404(
    db: AsyncSession,
    model: type[T],
    obj_id: int,
    detail: str,
    *,
    options: Sequence[Any] = (),
) -> T:
    """Объект по первичному ключу или 404.

    `options` — то, что нужно подгрузить сразу (`selectinload`), иначе
    сериализация ответа уйдёт в ленивую загрузку и упадёт в async-SQLAlchemy.
    """
    stmt = select(model).where(model.id == obj_id)
    if options:
        stmt = stmt.options(*options)
    result = await db.execute(stmt)
    return ensure_found(result.scalar_one_or_none(), detail)

"""Постраничная выдача списков.

Раньше все списки уходили на клиент целиком и фильтровались в браузере.
На небольших справочниках это незаметно, но карточки сотрудников и нормы
растут, и однажды страница начинает тянуть мегабайты.

Формат ответа одинаковый для всех списков:

    {"items": [...], "total": 1234, "page": 1, "page_size": 50, "pages": 25}

Чтобы списки не повторяли одно и то же, здесь три вещи:

    params: PageParams = Depends(pagination.params)   # query-параметры
    query = pagination.apply(base.order_by(...), params)   # limit/offset
    return pagination.page_of([Schema.model_validate(i) for i in items], total, params)
"""
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Annotated, Any, Generic, TypeVar

from fastapi import Depends, Query
from pydantic import BaseModel

T = TypeVar("T")

DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 200


@dataclass
class PageParams:
    page: int
    page_size: int

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.page_size


class Page(BaseModel, Generic[T]):
    """Единый конверт постраничного ответа."""

    items: list[T]
    total: int
    page: int
    page_size: int
    pages: int

    @classmethod
    def build(cls, items: Sequence[Any], total: int, page: int, page_size: int) -> "Page":
        pages = (total + page_size - 1) // page_size if page_size else 0
        return cls(
            items=list(items),
            total=total,
            page=page,
            page_size=page_size,
            pages=pages,
        )


def params(
    page: int = Query(1, ge=1, description="Номер страницы"),
    page_size: int = Query(
        DEFAULT_PAGE_SIZE,
        ge=1,
        le=MAX_PAGE_SIZE,
        description="Размер страницы",
    ),
) -> PageParams:
    """FastAPI-dependency: page/page_size с проверкой границ (иначе 422).

    Использование: `params: PageParams = Depends(pagination.params)`.
    """
    return PageParams(page=page, page_size=page_size)


PageDep = Annotated[PageParams, Depends(params)]


def apply(stmt: Any, page: PageParams) -> Any:
    """Добавляет к запросу limit/offset. Порядок задаёт вызывающий: без
    `order_by` Postgres вправе менять порядок между запросами, и страницы
    начнут дублироваться и пропускаться."""
    return stmt.offset(page.offset).limit(page.page_size)


def page_of(items: Sequence[Any], total: int, page: PageParams) -> Page:
    """Конверт ответа: items уже сериализованы, total — из count-запроса."""
    return Page.build(items, total=total, page=page.page, page_size=page.page_size)

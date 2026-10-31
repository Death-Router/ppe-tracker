"""Постраничная выдача списков.

Раньше все списки уходили на клиент целиком и фильтровались в браузере.
На небольших справочниках это незаметно, но карточки сотрудников и нормы
растут, и однажды страница начинает тянуть мегабайты.

Формат ответа одинаковый для всех списков:

    {"items": [...], "total": 1234, "page": 1, "page_size": 50, "pages": 25}
"""
from dataclasses import dataclass
from typing import Any, Generic, Sequence, TypeVar

from pydantic import BaseModel, Field

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


def normalize(page: int | None, page_size: int | None) -> PageParams:
    """Приводит параметры запроса к безопасным значениям."""
    page = max(1, int(page or 1))
    size = int(page_size or DEFAULT_PAGE_SIZE)
    size = max(1, min(size, MAX_PAGE_SIZE))
    return PageParams(page=page, page_size=size)


class PageQuery(BaseModel):
    """query-параметры пагинации для эндпоинтов."""

    page: int = Field(1, ge=1, description="Номер страницы, начиная с 1")
    page_size: int = Field(
        DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE, description="Размер страницы"
    )

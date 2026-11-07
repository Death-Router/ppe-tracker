"""Оптимистичная блокировка строк.

У изменяемых сущностей есть счётчик `version`. Клиент присылает ту версию,
которую видел; сервер сверяет её с базой. Расхождение — 409: без этой
проверки два человека молча перетирают правки друг друга.

Проверка была скопирована в девять endpoint'ов одинаковым блоком:

    if db_dept.version != dept_in.version:
        raise HTTPException(status_code=409, detail="Данные устарели")
"""
from fastapi import HTTPException, status


def ensure_version(current: int, client: int) -> None:
    """409, если запись изменилась с момента, когда клиент её прочитал."""
    if current != client:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Данные устарели",
        )

"""Расчёт даты окончания срока носки СИЗ.

Раньше срок считался как 365 дней за год и 30 дней за месяц: на високосном
году и на месяцах разной длины дата уезжала на несколько дней, а на длинных
периодах ошибка накапливалась заметно.
"""
from datetime import date
from typing import Optional

from dateutil.relativedelta import relativedelta

# Единицы нормы, для которых можно посчитать дату окончания
YEAR_UNITS = {"год", "года", "лет"}
MONTH_UNITS = {"месяц", "месяца", "месяцев"}


def parse_wear_period(value, unit: Optional[str]) -> Optional[relativedelta]:
    """Превращает норму («12», «месяц») в relativedelta.

    Возвращает None, если срок не выражается в календарных единицах
    (например, «до износа») или значение не число.
    """
    if value is None or not unit:
        return None

    unit_norm = str(unit).strip().lower()
    try:
        amount = int(str(value).strip())
    except (TypeError, ValueError):
        return None

    if amount <= 0:
        return None

    if unit_norm in YEAR_UNITS:
        return relativedelta(years=amount)
    if unit_norm in MONTH_UNITS:
        return relativedelta(months=amount)
    return None


def add_wear_period(issue_date: Optional[date], value, unit: Optional[str]) -> Optional[date]:
    """Дата окончания носки: календарные год/месяц, а не 365/30 дней.

    31 января + 1 месяц = 28/29 февраля (relativedelta сам приводит конец месяца),
    1 марта 2024 + 1 год = 1 марта 2025, хотя это 366 дней.
    """
    if issue_date is None:
        return None

    delta = parse_wear_period(value, unit)
    if delta is None:
        return None

    return issue_date + delta

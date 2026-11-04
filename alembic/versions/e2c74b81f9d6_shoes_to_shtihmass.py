"""Перевод размеров обуви на штихмассовую систему

Предыдущая миграция записала размеры так, как они обозначены на самой
обуви: валяная 24-35, боты 300-345, сапоги 280-330. В справочнике при этом
обычная обувь уже хранится в штихмассовых значениях (34-48), то есть в
одной таблице оказались три разные системы и выбрать размер было нельзя.

Теперь всё в штихмассовой системе:
  валяная    24-35   -> 37-48
  боты       300-345 -> 40-46
  сапоги     280-330 -> 41-46

Соответствие по справочным таблицам:
  24=37 25=38 26=39 27=40 28=41 29=42 30=43 31=44 32=45 33=46 34=47 35=48
  300=40 307=41 315=42 322=43 330=44 337=45 345=46
  280=41 290=42 300=43 310=44 320=45 330=46

Revision ID: e2c74b81f9d6
Revises: d5a8f21c4e37
Create Date: 2026-11-04
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e2c74b81f9d6"
down_revision: Union[str, Sequence[str], None] = "d5a8f21c4e37"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# (группа, {было: стало})
CONVERSIONS: list[tuple[str, dict[str, str]]] = [
    (
        "Обувь валяная",
        {
            "24": "37",
            "25": "38",
            "26": "39",
            "27": "40",
            "28": "41",
            "29": "42",
            "30": "43",
            "31": "44",
            "32": "45",
            "33": "46",
            "34": "47",
            "35": "48",
        },
    ),
    (
        "Боты диэлектрические",
        {
            "300": "40",
            "307": "41",
            "315": "42",
            "322": "43",
            "330": "44",
            "337": "45",
            "345": "46",
        },
    ),
    (
        "Сапоги рыбацкие, охотничьи зимние",
        {
            "280": "41",
            "290": "42",
            "300": "43",
            "310": "44",
            "320": "45",
            "330": "46",
        },
    ),
]


def upgrade() -> None:
    conn = op.get_bind()

    find_group = sa.text(
        "SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
    )
    update = sa.text(
        "UPDATE ppe_sizes SET size_value = CAST(:new_value AS varchar(50)) "
        "WHERE id = :size_id"
    )
    find_size = sa.text(
        "SELECT id FROM ppe_sizes "
        "WHERE size_group_id = :group_id "
        "  AND size_value = CAST(:old_value AS varchar(50)) "
        "  AND gender IS NULL"
    )
    delete = sa.text("DELETE FROM ppe_sizes WHERE id = :size_id")

    for group_name, mapping in CONVERSIONS:
        group_id = conn.execute(find_group, {"name": group_name}).scalar()
        if group_id is None:
            continue

        for old_value, new_value in mapping.items():
            params = {"group_id": group_id, "old_value": old_value}
            size_id = conn.execute(find_size, params).scalar()
            if size_id is None:
                # Размера с таким значением нет — например, миграцию уже
                # прогоняли или запись удалили вручную
                continue

            # Значение может уже существовать после пересчёта соседнего
            # размера: тогда старую запись просто убираем, чтобы не нарушить
            # уникальность (группа, значение, пол)
            clash = conn.execute(
                sa.text(
                    "SELECT id FROM ppe_sizes "
                    "WHERE size_group_id = :group_id "
                    "  AND size_value = CAST(:new_value AS varchar(50)) "
                    "  AND gender IS NULL "
                    "  AND id <> :size_id"
                ),
                {"group_id": group_id, "new_value": new_value, "size_id": size_id},
            ).scalar()

            if clash is not None:
                conn.execute(delete, {"size_id": size_id})
            else:
                conn.execute(update, {"size_id": size_id, "new_value": new_value})

    # Описание групп: убираем упоминание маркировки на обуви, оставляем
    # штихмассовый смысл — иначе подсказка противоречит данным
    conn.execute(
        sa.text(
            "UPDATE ppe_size_groups SET description = CAST(:description AS text) "
            "WHERE name = CAST(:name AS varchar(100))"
        ),
        {
            "name": "Обувь валяная",
            "description": "Размер в штихмассовой системе, 37-48. "
            "На самой обуви может быть указан другой номер: 24=37, 25=38, 26=39, "
            "27=40, 28=41, 29=42, 30=43, 31=44, 32=45, 33=46, 34=47, 35=48.",
        },
    )
    conn.execute(
        sa.text(
            "UPDATE ppe_size_groups SET description = CAST(:description AS text) "
            "WHERE name = CAST(:name AS varchar(100))"
        ),
        {
            "name": "Боты диэлектрические",
            "description": "Размер в штихмассовой системе, 40-46. "
            "На ботах может быть указан метрический размер в мм: "
            "300=40, 307=41, 315=42, 322=43, 330=44, 337=45, 345=46.",
        },
    )
    conn.execute(
        sa.text(
            "UPDATE ppe_size_groups SET description = CAST(:description AS text) "
            "WHERE name = CAST(:name AS varchar(100))"
        ),
        {
            "name": "Сапоги рыбацкие, охотничьи зимние",
            "description": "Размер в штихмассовой системе, 41-46. "
            "На сапогах может быть указан метрический размер в мм: "
            "280=41, 290=42, 300=43, 310=44, 320=45, 330=46.",
        },
    )


def downgrade() -> None:
    """Возвращает обозначения на обуви — обратное соответствие."""
    conn = op.get_bind()

    find_group = sa.text(
        "SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
    )
    update = sa.text(
        "UPDATE ppe_sizes SET size_value = CAST(:target AS varchar(50)) WHERE id = :size_id"
    )
    find_size = sa.text(
        "SELECT id FROM ppe_sizes "
        "WHERE size_group_id = :group_id "
        "  AND size_value = CAST(:current AS varchar(50)) "
        "  AND gender IS NULL"
    )

    for group_name, mapping in CONVERSIONS:
        group_id = conn.execute(find_group, {"name": group_name}).scalar()
        if group_id is None:
            continue

        for old_value, new_value in mapping.items():
            size_id = conn.execute(
                find_size, {"group_id": group_id, "current": new_value}
            ).scalar()
            if size_id is not None:
                conn.execute(update, {"size_id": size_id, "target": old_value})

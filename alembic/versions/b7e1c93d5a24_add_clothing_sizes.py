"""Размеры одежды по памятке «Как определить размер спецодежды»

Добавляет в группу «Костюмы» размеры из отраслевой памятки: 40-42 … 64-66
отдельно для мужчин и женщин. Группа у каждого размера одна, пол различает
записи — пара (size_group_id, size_value, gender) уникальна.

Роста из памятки не добавляются: рост хранится в карточке сотрудника.

Revision ID: b7e1c93d5a24
Revises: f4d2a8c71e60
Create Date: 2026-11-04
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "b7e1c93d5a24"
down_revision: Union[str, Sequence[str], None] = "f4d2a8c71e60"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

GROUP_NAME = "Костюмы"
GROUP_DESCRIPTION = (
    "Размер одежды по обхвату груди и талии (мужчины) или бёдер (женщины). "
    "Диапазоны — по памятке «Как определить размер спецодежды», 2017."
)

# Значения — как в таблицах памятки
SIZES_MEN = ["40-42", "44-46", "48-50", "52-54", "56-58", "60-62", "64-66"]
SIZES_WOMEN = ["40-42", "44-46", "48-50", "52-54", "56-58", "60-62", "64-66"]


def upgrade() -> None:
    conn = op.get_bind()

    # Группа может уже существовать: создаём только если её нет
    group_id = conn.execute(
        sa.text("SELECT id FROM ppe_size_groups WHERE name = :name"),
        {"name": GROUP_NAME},
    ).scalar()

    if group_id is None:
        group_id = conn.execute(
            sa.text(
                "INSERT INTO ppe_size_groups (name, description, version) "
                "VALUES (:name, :description, 1) RETURNING id"
            ),
            {"name": GROUP_NAME, "description": GROUP_DESCRIPTION},
        ).scalar()

    # Повторный запуск не должен плодить дубли: INSERT ... WHERE NOT EXISTS
    insert = sa.text(
        "INSERT INTO ppe_sizes (size_group_id, size_value, gender) "
        "SELECT :group_id, :size_value, :gender "
        "WHERE NOT EXISTS ("
        "  SELECT 1 FROM ppe_sizes "
        "  WHERE size_group_id = :group_id "
        "    AND size_value = :size_value "
        "    AND gender = :gender"
        ")"
    )

    for size_value in SIZES_MEN:
        conn.execute(insert, {"group_id": group_id, "size_value": size_value, "gender": "М"})

    for size_value in SIZES_WOMEN:
        conn.execute(insert, {"group_id": group_id, "size_value": size_value, "gender": "Ж"})


def downgrade() -> None:
    # Удаляем только эти размеры: остальные размеры группы не трогаем
    conn = op.get_bind()
    conn.execute(
        sa.text(
            "DELETE FROM ppe_sizes "
            "WHERE size_group_id IN (SELECT id FROM ppe_size_groups WHERE name = :name) "
            "AND size_value IN (:values)"
        ).bindparams(sa.bindparam("values", expanding=True)),
        {"name": GROUP_NAME, "values": SIZES_MEN},
    )

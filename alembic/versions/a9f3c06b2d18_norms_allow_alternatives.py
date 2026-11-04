"""Нормы выдачи: несколько записей на пару «должность + СИЗ»

Матрица норм выдачи (приказ Минтруда) содержит для одной должности и одного
вида СИЗ основное наименование и до четырёх альтернатив. Ограничение
uq_position_ppe_item разрешало только одну запись на пару, поэтому
альтернативы некуда было положить.

Теперь на пару может приходиться несколько норм. При выдаче берётся первая
(минимальный id) — срок носки считается по ней же.

Revision ID: a9f3c06b2d18
Revises: e2c74b81f9d6
Create Date: 2026-11-04
"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "a9f3c06b2d18"
down_revision: Union[str, Sequence[str], None] = "e2c74b81f9d6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

CONSTRAINT_NAME = "uq_position_ppe_item"


def upgrade() -> None:
    # Оставляем обычный индекс: поиск норм по должности и СИЗ остаётся быстрым
    op.drop_constraint(CONSTRAINT_NAME, "position_ppe_norms", type_="unique")
    op.create_index(
        "ix_position_ppe_norms_position_item",
        "position_ppe_norms",
        ["position_id", "ppe_item_id"],
    )


def downgrade() -> None:
    # Возврат возможен только если дублей нет — иначе БД откажется
    op.drop_index("ix_position_ppe_norms_position_item", table_name="position_ppe_norms")
    op.create_unique_constraint(
        CONSTRAINT_NAME, "position_ppe_norms", ["position_id", "ppe_item_id"]
    )

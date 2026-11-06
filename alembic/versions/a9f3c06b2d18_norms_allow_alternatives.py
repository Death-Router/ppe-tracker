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
    # Ограничение снимаем, только если оно есть: в цепочке миграций его
    # никогда не создавали (e1e06dfc6360 вместо create_unique_constraint
    # выдала drop_table), поэтому на чистой базе DROP CONSTRAINT падал бы
    # с UndefinedObject. IF EXISTS делает шаг no-op там, где ограничения нет,
    # и сохраняет прежнее поведение на базах, где оно успело появиться вручную.
    op.execute(f"ALTER TABLE position_ppe_norms DROP CONSTRAINT IF EXISTS {CONSTRAINT_NAME}")
    # Оставляем обычный индекс: поиск норм по должности и СИЗ остаётся быстрым
    op.create_index(
        "ix_position_ppe_norms_position_item",
        "position_ppe_norms",
        ["position_id", "ppe_item_id"],
        if_not_exists=True,
    )


def downgrade() -> None:
    # Возврат возможен только если дублей нет — иначе БД откажется.
    # Ограничение добавляем через IF NOT EXISTS: на базах, развёрнутых с нуля
    # после правки e1e06dfc6360, его нет, а на старых оно могло сохраниться —
    # create_unique_constraint упал бы на "already exists".
    op.drop_index("ix_position_ppe_norms_position_item", table_name="position_ppe_norms")
    op.execute(
        f"ALTER TABLE position_ppe_norms "
        f"ADD CONSTRAINT IF NOT EXISTS {CONSTRAINT_NAME} UNIQUE (position_id, ppe_item_id)"
    )

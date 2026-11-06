"""add gender to ppe_sizes

Revision ID: 42b7bb81cc04
Revises: 5b495550fcfc
Create Date: 2026-10-29 07:36:59.475855

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '42b7bb81cc04'
down_revision: Union[str, Sequence[str], None] = '5b495550fcfc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Добавляет колонку gender в ppe_sizes.

    Автогенерация вместо add_column выдала drop_table: Alembic не увидел
    таблицу, хотя её создал предыдущий шаг 5b495550fcfc. На чистой базе это
    удаляло таблицу, и следующие шаги 9dbb6662bf81 и f3bb1b7dee7d падали
    на её отсутствии. На рабочих базах ревизия уже отмечена применённой.
    """
    op.add_column('ppe_sizes', sa.Column('gender', sa.String(length=1), nullable=True))
    op.drop_constraint('uq_ppe_item_size', 'ppe_sizes', type_='unique')
    op.create_unique_constraint(
        'uq_ppe_item_size_gender', 'ppe_sizes', ['ppe_item_id', 'size_value', 'gender']
    )


def downgrade() -> None:
    """Возвращает схему 5b495550fcfc: без gender, с уникальностью на паре."""
    op.drop_constraint('uq_ppe_item_size_gender', 'ppe_sizes', type_='unique')
    op.create_unique_constraint('uq_ppe_item_size', 'ppe_sizes', ['ppe_item_id', 'size_value'])
    op.drop_column('ppe_sizes', 'gender')

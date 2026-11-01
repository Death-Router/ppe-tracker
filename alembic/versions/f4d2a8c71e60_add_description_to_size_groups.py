"""ppe_size_groups.description: пояснение к размерной группе

Названия вроде «Костюмы» или «Обувь» не говорят, что именно меряется.
Пояснение показывается в справочнике, чтобы пользователь понимал, какой
размер вводить.

Revision ID: f4d2a8c71e60
Revises: a1c4e7d92b30
Create Date: 2026-11-01
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "f4d2a8c71e60"
down_revision: Union[str, Sequence[str], None] = "a1c4e7d92b30"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Необязательное поле: существующие группы остаются без описания
    op.add_column(
        "ppe_size_groups",
        sa.Column("description", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("ppe_size_groups", "description")

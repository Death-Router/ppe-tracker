"""Справочник типовых отраслевых норм и связь с нормами выдачи

Графа «Пункт Норм» личной карточки учёта СИЗ ссылается на пункт приложения
к Положению. Раньше его негде было хранить: оставался только общий текст
«Приложение №1 к Положению…» в самой форме.

- `typical_norms` — справочник: пункт нормы (уникальный) и описание;
- `position_ppe_norms.typical_norm_id` — выпадающий список в норме выдачи.

Связь `ON DELETE RESTRICT`: пункт, на который ссылаются нормы, удалять
нельзя — иначе в карточке пропадёт основание выдачи.

Revision ID: e7b41c05a9d3
Revises: c4d9e2b71f30
Create Date: 2026-11-05
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "e7b41c05a9d3"
down_revision: Union[str, Sequence[str], None] = "c4d9e2b71f30"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "typical_norms",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("clause", sa.String(length=50), nullable=False),
        sa.Column("description", sa.String(length=500), nullable=False),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    # Пункт нормы — то, что вписывают в карточку; дубли означали бы, что
    # у одного основания два разных описания
    op.create_index("ix_typical_norms_clause", "typical_norms", ["clause"], unique=True)

    op.add_column(
        "position_ppe_norms",
        sa.Column("typical_norm_id", sa.Integer(), nullable=True),
    )
    op.create_foreign_key(
        "position_ppe_norms_typical_norm_id_fkey",
        "position_ppe_norms",
        "typical_norms",
        ["typical_norm_id"],
        ["id"],
        ondelete="RESTRICT",
    )


def downgrade() -> None:
    op.drop_constraint(
        "position_ppe_norms_typical_norm_id_fkey",
        "position_ppe_norms",
        type_="foreignkey",
    )
    op.drop_column("position_ppe_norms", "typical_norm_id")

    op.drop_index("ix_typical_norms_clause", table_name="typical_norms")
    op.drop_table("typical_norms")

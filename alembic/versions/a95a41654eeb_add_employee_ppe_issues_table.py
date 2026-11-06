"""add employee_ppe_issues table

Revision ID: a95a41654eeb
Revises: e1e06dfc6360
Create Date: 2026-10-29 05:19:38.451813

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a95a41654eeb'
down_revision: Union[str, Sequence[str], None] = 'e1e06dfc6360'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Индексы ix_position_ppe_norms_position_id / _ppe_item_id здесь больше не
    # удаляются: их никогда не создавалось. bd09b9140447 создаёт только
    # первичный ключ и два внешних ключа, а составной индекс
    # ix_position_ppe_norms_position_item появляется позже, в a9f3c06b2d18.
    # На чистой базе drop_index падал с "index does not exist".
    op.create_table('employee_ppe_issues',
    sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
    sa.Column('employee_id', sa.Integer(), nullable=False),
    sa.Column('ppe_item_id', sa.Integer(), nullable=False),
    sa.Column('issue_date', sa.Date(), nullable=False),
    sa.Column('quantity', sa.String(length=50), nullable=False),
    sa.Column('size_value', sa.String(length=50), nullable=True),
    sa.Column('expiry_date', sa.Date(), nullable=True),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.ForeignKeyConstraint(['employee_id'], ['employees.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['ppe_item_id'], ['ppe_items.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.alter_column('position_ppe_norms', 'wear_period_value',
               existing_type=sa.VARCHAR(length=50),
               comment='Например: 1, 12, 6',
               existing_nullable=False)
    op.alter_column('position_ppe_norms', 'wear_period_unit',
               existing_type=sa.VARCHAR(length=20),
               comment='год, месяц, до износа',
               existing_nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    op.alter_column('position_ppe_norms', 'wear_period_unit',
               existing_type=sa.VARCHAR(length=20),
               comment=None,
               existing_comment='год, месяц, до износа',
               existing_nullable=False)
    op.alter_column('position_ppe_norms', 'wear_period_value',
               existing_type=sa.VARCHAR(length=50),
               comment=None,
               existing_comment='Например: 1, 12, 6',
               existing_nullable=False)
    op.drop_table('employee_ppe_issues')

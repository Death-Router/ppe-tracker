"""add parent_id to departments

Revision ID: 9dbb6662bf81
Revises: 42b7bb81cc04
Create Date: 2026-10-29 11:16:25.382918

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9dbb6662bf81'
down_revision: Union[str, Sequence[str], None] = '42b7bb81cc04'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Добавляет departments.parent_id.

    Автогенерация добавила сюда ещё drop_index('ix_ppe_sizes_ppe_item_id') и
    drop_table('ppe_sizes'). Таблицу не удаляем: 42b7bb81cc04 её больше не
    уничтожает (её drop_table убран), а индекса ix_ppe_sizes_ppe_item_id
    не существовало вовсе — 5b495550fcfc его не создаёт.
    """
    op.add_column('departments', sa.Column('parent_id', sa.Integer(), nullable=True))
    op.create_foreign_key(None, 'departments', 'departments', ['parent_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    """Убирает departments.parent_id."""
    op.drop_constraint(None, 'departments', type_='foreignkey')
    op.drop_column('departments', 'parent_id')

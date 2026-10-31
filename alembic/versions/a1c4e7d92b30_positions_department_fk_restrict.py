"""positions.department_id: CASCADE -> RESTRICT

Удаление подразделения раньше молча уносило на уровне БД все его должности,
даже если приложение забывало проверить. Теперь СУБД сама не даст этого сделать.

Revision ID: a1c4e7d92b30
Revises: c63571f88efc
Create Date: 2026-10-31
"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "a1c4e7d92b30"
down_revision: Union[str, Sequence[str], None] = "c63571f88efc"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

CONSTRAINT_NAME = "positions_department_id_fkey"


def upgrade() -> None:
    op.drop_constraint(CONSTRAINT_NAME, "positions", type_="foreignkey")
    op.create_foreign_key(
        CONSTRAINT_NAME,
        "positions",
        "departments",
        ["department_id"],
        ["id"],
        ondelete="RESTRICT",
    )


def downgrade() -> None:
    op.drop_constraint(CONSTRAINT_NAME, "positions", type_="foreignkey")
    op.create_foreign_key(
        CONSTRAINT_NAME,
        "positions",
        "departments",
        ["department_id"],
        ["id"],
        ondelete="CASCADE",
    )

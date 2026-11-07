"""фото сотрудника: таблица employee_photos

Файл фото живёт в каталоге PHOTO_DIR (том данных), в БД — метаданные:
имя файла, тип, размер и sha256. См. app/models/employee_photo.py.

Revision ID: a4d1f7c2e9b5
Revises: e7b41c05a9d3
Create Date: 2026-11-07
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "a4d1f7c2e9b5"
down_revision: Union[str, Sequence[str], None] = "e7b41c05a9d3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "employee_photos",
        sa.Column("employee_id", sa.Integer(), nullable=False),
        # Только имя файла внутри PHOTO_DIR — без каталогов, чтобы значение
        # из формы нельзя было превратить в путь («../../etc/passwd»)
        sa.Column("filename", sa.String(length=64), nullable=False),
        sa.Column("mime_type", sa.String(length=50), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column(
            "uploaded_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["employee_id"], ["employees.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("employee_id"),
    )


def downgrade() -> None:
    op.drop_table("employee_photos")

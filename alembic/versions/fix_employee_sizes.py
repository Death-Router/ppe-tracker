"""rename category_id to size_group_id in employee_ppe_sizes

Revision ID: fix_employee_sizes
Revises: cc31f1fe06fd
Create Date: 2026-10-30
"""
from alembic import op
import sqlalchemy as sa

revision = 'fix_employee_sizes'
down_revision = 'cc31f1fe06fd'
branch_labels = None
depends_on = None

def upgrade():
    # Переименовываем колонку
    op.alter_column('employee_ppe_sizes', 'category_id', new_column_name='size_group_id')
    # Удаляем старый внешний ключ (если есть) и создаем новый
    # (Alembic может не знать имя, поэтому используем raw SQL)
    op.execute("ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS employee_ppe_sizes_category_id_fkey")
    op.execute("ALTER TABLE employee_ppe_sizes ADD CONSTRAINT employee_ppe_sizes_size_group_id_fkey FOREIGN KEY (size_group_id) REFERENCES ppe_size_groups(id) ON DELETE CASCADE")
    # Удаляем старый уникальный ключ и создаем новый
    op.execute("ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS uq_employee_category_size")
    op.execute("ALTER TABLE employee_ppe_sizes ADD CONSTRAINT uq_employee_size_group UNIQUE (employee_id, size_group_id)")

def downgrade():
    op.alter_column('employee_ppe_sizes', 'size_group_id', new_column_name='category_id')
    op.execute("ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS employee_ppe_sizes_size_group_id_fkey")
    op.execute("ALTER TABLE employee_ppe_sizes ADD CONSTRAINT employee_ppe_sizes_category_id_fkey FOREIGN KEY (category_id) REFERENCES ppe_categories(id) ON DELETE CASCADE")
    op.execute("ALTER TABLE employee_ppe_sizes DROP CONSTRAINT IF EXISTS uq_employee_size_group")
    op.execute("ALTER TABLE employee_ppe_sizes ADD CONSTRAINT uq_employee_category_size UNIQUE (employee_id, category_id)")

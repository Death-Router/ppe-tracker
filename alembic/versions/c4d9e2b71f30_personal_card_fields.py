"""Поля формы личной карточки учёта СИЗ (приложение № 4 к Положению)

Что добавлено и зачем — по графам формы ПАО «Ростелеком» (редакция 2,
приказ 01/01/4523/24 от 13.02.2025):

- `ppe_items.model`, `ppe_items.protection_class` — графа 2 оборотной
  стороны «Модель, марка, артикул, класс защиты СИЗ».
- `employees.personal_card_number` — номер личной карточки на лицевой
  стороне. Уникальный: это номер документа.
- `employee_ppe_issues.issue_method` — графа 5 «лично/дозатор», только для
  дерматологических СИЗ (сноска <*>).
- `employee_ppe_issues.returned_date`, `returned_quantity`,
  `write_off_act_date`, `write_off_act_number` — графы 7-10 «Возвращено»
  и «Акт списания» (сноска <**>).
- размерная группа «СИЗОД» — на лицевой стороне под размер СИЗОД отведена
  отдельная строка, а такой группы в справочнике не было.

Revision ID: c4d9e2b71f30
Revises: a9f3c06b2d18
Create Date: 2026-11-05
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "c4d9e2b71f30"
down_revision: Union[str, Sequence[str], None] = "a9f3c06b2d18"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SIZOD_GROUP = "СИЗОД"
SIZOD_DESCRIPTION = (
    "Средства защиты органов дыхания. Размер зависит от модели: "
    "у респираторов — S, M, L или 1, 2, 3 (класс защиты FFP1-FFP3), "
    "у противогазов — по маске. Значения задаются в справочнике размеров."
)


def upgrade() -> None:
    op.add_column("ppe_items", sa.Column("model", sa.String(length=255), nullable=True))
    op.add_column(
        "ppe_items", sa.Column("protection_class", sa.String(length=100), nullable=True)
    )

    op.add_column(
        "employees", sa.Column("personal_card_number", sa.String(length=30), nullable=True)
    )
    # NULL-номера уникальность не нарушают: у ранее заведённых сотрудников
    # номера карточек нет, его вписывают по бумажным карточкам.
    op.create_unique_constraint(
        "uq_employees_personal_card_number", "employees", ["personal_card_number"]
    )

    op.add_column(
        "employee_ppe_issues", sa.Column("issue_method", sa.String(length=20), nullable=True)
    )
    op.add_column(
        "employee_ppe_issues", sa.Column("returned_date", sa.Date(), nullable=True)
    )
    op.add_column(
        "employee_ppe_issues",
        sa.Column("returned_quantity", sa.String(length=50), nullable=True),
    )
    op.add_column(
        "employee_ppe_issues", sa.Column("write_off_act_date", sa.Date(), nullable=True)
    )
    op.add_column(
        "employee_ppe_issues",
        sa.Column("write_off_act_number", sa.String(length=50), nullable=True),
    )

    conn = op.get_bind()
    # Параметр приводим явно: asyncpg не выводит тип, когда одно значение
    # используется и в SELECT, и в сравнении с varchar-колонкой
    existing = conn.execute(
        sa.text("SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"),
        {"name": SIZOD_GROUP},
    ).scalar()

    if existing is None:
        conn.execute(
            sa.text(
                "INSERT INTO ppe_size_groups (name, description, version) "
                "VALUES (CAST(:name AS varchar(100)), CAST(:description AS text), 1)"
            ),
            {"name": SIZOD_GROUP, "description": SIZOD_DESCRIPTION},
        )


def downgrade() -> None:
    conn = op.get_bind()

    # Группу удаляем только если её никто не использовал: иначе пропадут
    # СИЗ и размеры, привязанные к ней уже после миграции
    in_use = conn.execute(
        sa.text(
            "SELECT 1 FROM ppe_items WHERE size_group_id IN ("
            "  SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
            ") UNION ALL SELECT 1 FROM ppe_sizes WHERE size_group_id IN ("
            "  SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
            ") LIMIT 1"
        ),
        {"name": SIZOD_GROUP},
    ).scalar()

    if in_use is None:
        conn.execute(
            sa.text("DELETE FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"),
            {"name": SIZOD_GROUP},
        )

    op.drop_column("employee_ppe_issues", "write_off_act_number")
    op.drop_column("employee_ppe_issues", "write_off_act_date")
    op.drop_column("employee_ppe_issues", "returned_quantity")
    op.drop_column("employee_ppe_issues", "returned_date")
    op.drop_column("employee_ppe_issues", "issue_method")

    op.drop_constraint("uq_employees_personal_card_number", "employees", type_="unique")
    op.drop_column("employees", "personal_card_number")

    op.drop_column("ppe_items", "protection_class")
    op.drop_column("ppe_items", "model")

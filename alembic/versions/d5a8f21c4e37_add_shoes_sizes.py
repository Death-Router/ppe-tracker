"""Размеры обуви: обычная, валяная, боты диэлектрические, сапоги рыбацкие

Данные из справочных таблиц по спецобуви.

Первая таблица — соответствие метрической (длина стопы, мм) и штихмассовой
систем: 34-40 у женской обуви, 39-48 у мужской.

Вторая таблица — виды обуви, где маркировка на самой обуви не совпадает со
штихмассовым размером. Размером считается то число, что написано на обуви:
  валяная 24-35   (штихмасс 37-48)
  боты диэлектрические 300-345 (штихмасс 40-46)
  сапоги рыбацкие 280-330 (штихмасс 41-46)
Соответствие перечислено в описании группы, чтобы пользователь видел его
при выборе размера.

Revision ID: d5a8f21c4e37
Revises: b7e1c93d5a24
Create Date: 2026-11-04
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "d5a8f21c4e37"
down_revision: Union[str, Sequence[str], None] = "b7e1c93d5a24"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SHOES_GROUP = "Обувь"

# (название группы, описание, значения размеров, пол)
GROUPS: list[tuple[str, str, list[str], str | None]] = [
    (
        "Обувь",
        "Обычная спецобувь. Метрическая система (длина стопы, мм) и "
        "штихмассовая: Ж 217-262 мм = 34-40, М 247-320 мм = 39-48. "
        "Интервал между смежными размерами 7,5 мм.",
        ["34", "35", "36", "37", "38", "39", "40"],
        "Ж",
    ),
    (
        "Обувь",
        "Обычная спецобувь. Метрическая система (длина стопы, мм) и "
        "штихмассовая: Ж 217-262 мм = 34-40, М 247-320 мм = 39-48. "
        "Интервал между смежными размерами 7,5 мм.",
        ["39", "40", "41", "42", "43", "44", "45", "46", "47", "48"],
        "М",
    ),
    (
        "Обувь валяная",
        "Размер на обуви (24-35) соответствует штихмассовому 37-48: "
        "24=37, 25=38, 26=39, 27=40, 28=41, 29=42, 30=43, "
        "31=44, 32=45, 33=46, 34=47, 35=48.",
        ["24", "25", "26", "27", "28", "29", "30", "31", "32", "33", "34", "35"],
        None,
    ),
    (
        "Боты диэлектрические",
        "Размер на боты (300-345) соответствует штихмассовому 40-46: "
        "300=40, 307=41, 315=42, 322=43, 330=44, 337=45, 345=46.",
        ["300", "307", "315", "322", "330", "337", "345"],
        None,
    ),
    (
        "Сапоги рыбацкие, охотничьи зимние",
        "Размер на сапоги (280-330) соответствует штихмассовому 41-46: "
        "280=41, 290=42, 300=43, 310=44, 320=45, 330=46.",
        ["280", "290", "300", "310", "320", "330"],
        None,
    ),
]


def upgrade() -> None:
    conn = op.get_bind()

    # Параметры приводим явно: asyncpg не выводит тип, если одно значение
    # используется и в SELECT, и в сравнении с колонкой (text против varchar)
    find_group = sa.text(
        "SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
    )
    create_group = sa.text(
        "INSERT INTO ppe_size_groups (name, description, version) "
        "VALUES (CAST(:name AS varchar(100)), CAST(:description AS text), 1) "
        "RETURNING id"
    )
    # Для gender = NULL сравнение идёт через IS NULL: asyncpg не выводит тип
    # для NULL-параметра внутри CAST(...) и падает на подготовке запроса
    exists_with_gender = sa.text(
        "SELECT 1 FROM ppe_sizes "
        "WHERE size_group_id = :group_id "
        "  AND size_value = CAST(:size_value AS varchar(50)) "
        "  AND gender = CAST(:gender AS varchar(1))"
    )
    exists_no_gender = sa.text(
        "SELECT 1 FROM ppe_sizes "
        "WHERE size_group_id = :group_id "
        "  AND size_value = CAST(:size_value AS varchar(50)) "
        "  AND gender IS NULL"
    )
    insert_with_gender = sa.text(
        "INSERT INTO ppe_sizes (size_group_id, size_value, gender) "
        "VALUES (:group_id, CAST(:size_value AS varchar(50)), CAST(:gender AS varchar(1)))"
    )
    insert_no_gender = sa.text(
        "INSERT INTO ppe_sizes (size_group_id, size_value, gender) "
        "VALUES (:group_id, CAST(:size_value AS varchar(50)), NULL)"
    )

    def ensure_group(name: str, description: str) -> int:
        group_id = conn.execute(find_group, {"name": name}).scalar()
        if group_id is None:
            group_id = conn.execute(
                create_group, {"name": name, "description": description}
            ).scalar()
        return group_id

    for name, description, values, gender in GROUPS:
        group_id = ensure_group(name, description)

        # Описание дописываем и существующей группе: у «Обувь» оно могло
        # быть пустым, а соответствие размеров полезно видеть при выборе
        conn.execute(
            sa.text(
                "UPDATE ppe_size_groups SET description = CAST(:description AS text) "
                "WHERE id = :group_id "
                "  AND (description IS NULL OR description = '')"
            ),
            {"group_id": group_id, "description": description},
        )

        for size_value in values:
            check = exists_with_gender if gender else exists_no_gender
            add = insert_with_gender if gender else insert_no_gender
            params = {"group_id": group_id, "size_value": size_value, "gender": gender}

            if conn.execute(check, params).scalar() is None:
                conn.execute(add, params)


def downgrade() -> None:
    conn = op.get_bind()

    # Удаляем только эти размеры: остальные размеры групп не трогаем
    delete_with_gender = sa.text(
        "DELETE FROM ppe_sizes "
        "WHERE size_group_id IN ("
        "  SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
        ") "
        "AND size_value = ANY(CAST(:values AS varchar(50)[])) "
        "AND gender = CAST(:gender AS varchar(1))"
    )
    delete_no_gender = sa.text(
        "DELETE FROM ppe_sizes "
        "WHERE size_group_id IN ("
        "  SELECT id FROM ppe_size_groups WHERE name = CAST(:name AS varchar(100))"
        ") "
        "AND size_value = ANY(CAST(:values AS varchar(50)[])) "
        "AND gender IS NULL"
    )

    for name, _description, values, gender in GROUPS:
        stmt = delete_with_gender if gender else delete_no_gender
        conn.execute(stmt, {"name": name, "values": values, "gender": gender})

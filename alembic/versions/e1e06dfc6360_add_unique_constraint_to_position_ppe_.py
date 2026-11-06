"""add unique constraint to position_ppe_norms

Ревизия оставлена пустой (upgrade и downgrade — pass).

История: автогенерация пришла к выводу, что уникального ограничения на паре
«должность + СИЗ» нет, и вместо `create_unique_constraint` выдала
`drop_table('position_ppe_norms')` — видимо, Alembic не увидел таблицу.
На работающей базе это прошло незаметно только потому, что строки миграций
применялись по одной в разное время и таблица к тому моменту уже была
пересоздана; на чистой базе `drop_table` удаляет таблицу, созданную
предыдущей ревизией bd09b9140447, и следующий шаг a95a41654eeb падает на
её колонках и индексах.

Ограничение `uq_position_ppe_item` в цепочке никогда не создавалось.
Настоящее решение — миграция a9f3c06b2d18, которая снимает ограничение
(если оно есть) и ставит обычный индекс.

На рабочих базах ревизия уже отмечена в alembic_version, поэтому для них
замена тела на `pass` ничего не меняет.

Revision ID: e1e06dfc6360
Revises: bd09b9140447
Create Date: 2026-10-28 13:52:57.199233

"""
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision: str = 'e1e06dfc6360'
down_revision: Union[str, Sequence[str], None] = 'bd09b9140447'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Ничего не делает — см. пояснение в docstring модуля.

    Автогенерация решила, что таблицы нет, и выдала `drop_table`, хотя её
    создал предыдущий шаг bd09b9140447. На чистой базе это уничтожало
    таблицу, и следующий шаг a95a41654eeb падал на её колонках.
    На рабочей базе ревизия уже отмечена применённой, поэтому для неё
    замена на `pass` ничего не меняет.
    """
    pass


def downgrade() -> None:
    """Ничего не делает.

    Раньше здесь был `create_table`: откат e1e06dfc6360 создавал таблицу,
    которая к этому моменту уже существует (её создаёт bd09b9140447),
    и падал бы на "relation already exists".
    """
    pass

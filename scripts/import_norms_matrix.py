"""Разбор матрицы норм выдачи СИЗ и отчёт о том, что будет импортировано.

Скрипт ничего не пишет в базу: он читает Excel и показывает, как данные
лягут в справочники. Запуск:

    python scripts/import_norms_matrix.py "путь.xlsx" --report
    python scripts/import_norms_matrix.py "путь.xlsx" --apply

Во втором случае нужен доступ к базе (переменные окружения приложения).
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import openpyxl

SHEET = "Нормы СИЗиСС по должности"

# Колонки листа (0-based)
COL_POSITION = 0
COL_KIND = 1
COL_TYPE = 4
COL_ITEM_MAIN = 6
COL_NORM_MAIN = 7
# Пары «наименование — норма» для альтернатив 1..4
COL_ALTERNATIVES = [(8, 9), (10, 11), (12, 13), (14, 15)]

# Норма выдачи -> (значение, единица) для wear_period_value / wear_period_unit
PERIOD_RE = re.compile(r"на\s+(\d+)\s*(год|года|лет)", re.IGNORECASE)

@dataclass
class NormRow:
    position: str
    kind: str
    protection_type: str
    item_name: str
    raw_norm: str
    quantity: str
    period_value: str
    period_unit: str
    alternative_of: str | None = None


@dataclass
class Report:
    rows_total: int = 0
    positions: set[str] = field(default_factory=set)
    items: set[str] = field(default_factory=set)
    alternatives: int = 0
    period_parsed: int = 0
    period_unknown: int = 0
    period_examples: Counter = field(default_factory=Counter)
    no_item: int = 0

    def as_text(self) -> str:
        lines = [
            f"Строк разобрано:              {self.rows_total}",
            f"Должностей:                   {len(self.positions)}",
            f"Наименований СИЗ:             {len(self.items)}",
            f"Из них альтернатив:           {self.alternatives}",
            "",
            f"Срок носки разобран:          {self.period_parsed}",
            f"Срок носки не разобран:       {self.period_unknown}",
        ]
        if self.period_examples:
            lines.append("  частые варианты без срока:")
            for text, count in self.period_examples.most_common(6):
                lines.append(f"    {count:5}  {text[:70]}")
        if self.no_item:
            lines.append("")
            lines.append(f"Строк без наименования СИЗ:   {self.no_item}")
        return "\n".join(lines)


def parse_norm(raw: str) -> tuple[str, str, str]:
    """Возвращает (количество, значение срока, единицу срока).

    Срок в файле указан явно только для «1 шт. на 2 года» — остальные
    значения задают количество за период, а сам период в ЕТН не выписан.
    Для них ставим «до износа»: срок не считается, но норма видна.

    Примеры:
      «1 шт. на 2 года»  -> («1 шт.», 2, год)
      «1 шт.»            -> («1 шт.», 1, до износа)
      «12 пар»           -> («12 пар», 1, до износа)
      «по поясам»        -> (1, 1, до износа)   — срок зависит от пояса
    """
    text = " ".join(str(raw or "").split())
    if not text:
        return "1", "1", "до износа"

    # Явный срок: «... на N год(а/лет)»
    match = PERIOD_RE.search(text)
    if match:
        quantity = text[: match.start()].strip(" .,") or "1"
        return quantity, match.group(1), "год"

    # «по поясам» — срок определяется климатическим поясом, количества нет
    if text.lower().startswith("по поясам"):
        return "1", "1", "до износа"

    # Остальное — количество (шт., пар, мл), срок не указан
    return text, "1", "до износа"


def read_rows(path: Path, with_alternatives: bool = False) -> tuple[list[NormRow], Report]:
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    if SHEET not in wb.sheetnames:
        raise SystemExit(f"Лист «{SHEET}» не найден. Есть: {', '.join(wb.sheetnames)}")

    ws = wb[SHEET]
    rows: list[NormRow] = []
    report = Report()

    for row in ws.iter_rows(min_row=3, values_only=True):
        if not row or not row[COL_POSITION]:
            continue

        position = " ".join(str(row[COL_POSITION]).split())
        kind = " ".join(str(row[COL_KIND] or "").split())
        ptype = " ".join(str(row[COL_TYPE] or "").split())

        main_name = " ".join(str(row[COL_ITEM_MAIN] or "").split())
        if not main_name:
            report.no_item += 1
        else:
            report.rows_total += 1
            report.positions.add(position)
            report.items.add(main_name)

            quantity, value, unit = parse_norm(row[COL_NORM_MAIN])
            if unit == "до износа":
                report.period_unknown += 1
                report.period_examples[" ".join(str(row[COL_NORM_MAIN] or "").split())] += 1
            else:
                report.period_parsed += 1

            rows.append(
                NormRow(
                    position=position,
                    kind=kind,
                    protection_type=ptype,
                    item_name=main_name,
                    raw_norm=" ".join(str(row[COL_NORM_MAIN] or "").split()),
                    quantity=quantity,
                    period_value=value,
                    period_unit=unit,
                )
            )

        # Альтернативы: по умолчанию пропускаем. Они означают «можно выдать
        # любое из перечисленных», и импорт всех вариантов раздувает нормы
        # втрое, ничего не добавляя к самой выдаче
        if not with_alternatives:
            continue

        for name_idx, norm_idx in COL_ALTERNATIVES:
            alt_name = " ".join(str(row[name_idx] or "").split())
            if not alt_name:
                continue

            report.alternatives += 1
            report.items.add(alt_name)

            quantity, value, unit = parse_norm(row[norm_idx])
            if unit == "до износа":
                report.period_unknown += 1
                report.period_examples[" ".join(str(row[norm_idx] or "").split())] += 1
            else:
                report.period_parsed += 1

            rows.append(
                NormRow(
                    position=position,
                    kind=kind,
                    protection_type=ptype,
                    item_name=alt_name,
                    raw_norm=" ".join(str(row[norm_idx] or "").split()),
                    quantity=quantity,
                    period_value=value,
                    period_unit=unit,
                    alternative_of=main_name or None,
                )
            )

    wb.close()
    return rows, report


def apply_rows(rows: list[NormRow], department_id: int) -> int:
    """Пишет нормы в базу. Существующие записи не трогает.

    Логика:
      - должность ищется по названию в указанном подразделении, при
        отсутствии создаётся;
      - наименование СИЗ ищется по названию, при отсутствии создаётся;
      - норма добавляется, только если пары «должность + СИЗ» ещё нет:
        повторный запуск не создаёт дублей.
    """
    import asyncio

    from sqlalchemy import select

    from app.db.session import async_session_maker
    from app.models.department import Department
    from app.models.position import Position
    from app.models.position_ppe_norm import PositionPpeNorm
    from app.models.ppe_item import PpeItem

    async def run() -> int:
        async with async_session_maker() as db:
            dept = await db.get(Department, department_id)
            if dept is None:
                print(f"Подразделение id={department_id} не найдено")
                return 1

            print(f"Подразделение: {dept.name} (id={dept.id})")
            print()

            # Кэши: названия уникальны в пределах своих справочников
            positions: dict[str, Position] = {
                p.name: p for p in (await db.execute(select(Position))).scalars()
            }
            items: dict[str, PpeItem] = {
                i.name: i for i in (await db.execute(select(PpeItem))).scalars()
            }

            existing = {
                (norm.position_id, norm.ppe_item_id)
                for norm in (await db.execute(select(PositionPpeNorm))).scalars()
            }

            created_positions = created_items = created_norms = skipped = 0

            for row in rows:
                position = positions.get(row.position)
                if position is None:
                    position = Position(name=row.position, department_id=department_id)
                    db.add(position)
                    await db.flush()
                    positions[row.position] = position
                    created_positions += 1

                item = items.get(row.item_name)
                if item is None:
                    item = PpeItem(name=row.item_name)
                    db.add(item)
                    await db.flush()
                    items[row.item_name] = item
                    created_items += 1

                key = (position.id, item.id)
                if key in existing:
                    skipped += 1
                    continue

                db.add(
                    PositionPpeNorm(
                        position_id=position.id,
                        ppe_item_id=item.id,
                        wear_period_value=row.period_value,
                        wear_period_unit=row.period_unit,
                        quantity=row.quantity,
                    )
                )
                existing.add(key)
                created_norms += 1

            await db.commit()

            print(f"Создано должностей:      {created_positions}")
            print(f"Создано наименований СИЗ: {created_items}")
            print(f"Добавлено норм:          {created_norms}")
            print(f"Пропущено (уже были):    {skipped}")
            return 0

    return asyncio.run(run())


def main() -> int:
    parser = argparse.ArgumentParser(description="Импорт матрицы норм выдачи СИЗ")
    parser.add_argument("file", type=Path, help="путь к xlsx")
    parser.add_argument("--report", action="store_true", help="только отчёт, без записи")
    parser.add_argument("--apply", action="store_true", help="записать в базу")
    parser.add_argument(
        "--with-alternatives",
        action="store_true",
        help="включить альтернативы (по умолчанию только основные нормы)",
    )
    parser.add_argument(
        "--department-id",
        type=int,
        help="подразделение, к которому привязать создаваемые должности",
    )
    args = parser.parse_args()

    if not args.file.exists():
        print(f"Файл не найден: {args.file}")
        return 1

    _rows, report = read_rows(args.file, with_alternatives=args.with_alternatives)

    print(f"Файл: {args.file.name}")
    print(f"Лист: {SHEET}")
    print()
    print(report.as_text())
    print()

    if args.report or not args.apply:
        print("Запись в базу не выполнялась (укажите --apply).")
        return 0

    if not args.department_id:
        print("Для записи укажите подразделение: --department-id N")
        print("  1. Вы уже видели отчёт выше.")
        print("  2. При повторном запуске используйте --report, чтобы не писать.")
        return 1

    return apply_rows(_rows, args.department_id)


if __name__ == "__main__":
    sys.exit(main())

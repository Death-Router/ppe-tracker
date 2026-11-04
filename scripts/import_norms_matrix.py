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


def read_rows(path: Path) -> tuple[list[NormRow], Report]:
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

        # Альтернативы: та же должность, другое наименование СИЗ
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Импорт матрицы норм выдачи СИЗ")
    parser.add_argument("file", type=Path, help="путь к xlsx")
    parser.add_argument("--report", action="store_true", help="только отчёт, без записи")
    parser.add_argument("--apply", action="store_true", help="записать в базу")
    args = parser.parse_args()

    if not args.file.exists():
        print(f"Файл не найден: {args.file}")
        return 1

    _rows, report = read_rows(args.file)

    print(f"Файл: {args.file.name}")
    print(f"Лист: {SHEET}")
    print()
    print(report.as_text())
    print()

    if args.report or not args.apply:
        print("Запись в базу не выполнялась (укажите --apply).")
        return 0

    print("Режим записи пока не реализован — сначала проверьте отчёт.")
    return 1


if __name__ == "__main__":
    sys.exit(main())

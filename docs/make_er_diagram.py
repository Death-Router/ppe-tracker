#!/usr/bin/env python3
"""Схема БД PPE Tracker в формате MS Visio (.vsdx).

Скрипт читает фактическую схему из работающей базы (information_schema через
`docker compose exec db psql`), раскладывает таблицы по странице A3-альбом и
собирает .vsdx: каркас берётся из `er_template.vsdx` (пустой документ Visio),
поэтому файл открывается в Visio без магии.

Запуск из корня проекта:

    .venv/bin/python docs/make_er_diagram.py

Почему так, а не картинкой: схема в репозитории должна обновляться одной
командой после миграции, а не перерисовываться руками.
"""
from __future__ import annotations

import math
import re
import subprocess
import zipfile
from dataclasses import dataclass, field
from datetime import date
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

PROJECT_ROOT = __file__.rsplit("/docs/", 1)[0]
TEMPLATE = f"{PROJECT_ROOT}/docs/er_template.vsdx"
OUTPUT = f"{PROJECT_ROOT}/docs/ppe-tracker-db-schema.vsdx"
MERMAID = f"{PROJECT_ROOT}/docs/db-schema.md"
PAGE_NAME = "Схема БД"

# Размер страницы и геометрия таблиц (дюймы — единица Visio по умолчанию)
PAGE_W = 19.4
PAGE_H = 10.6
BOX_W = 4.3
HEADER_H = 0.34
ROW_H = 0.19
PAD_H = 0.08

INK = "#1F2430"
BRAND = "#5B2C8A"
ACCENT = "#FF6600"
LINE = "#B9B2C7"

# Раскладка: таблица -> (левая граница, отступ сверху). Порядок выбран так,
# чтобы связи шли слева направо и почти не пересекались:
# организация -> сотрудники -> их размеры и выдачи | нормы -> СИЗ -> справочники
LAYOUT: dict[str, tuple[float, float]] = {
    "departments": (0.5, 1.5),
    "positions": (0.5, 3.3),
    "users": (0.5, 5.1),
    "alembic_version": (0.5, 7.6),
    "employees": (5.1, 1.5),
    "employee_ppe_sizes": (5.1, 5.2),
    "employee_ppe_issues": (5.1, 6.9),
    "position_ppe_norms": (9.7, 1.5),
    "typical_norms": (9.7, 4.0),
    "ppe_items": (9.7, 5.7),
    "ppe_functions": (14.3, 1.5),
    "ppe_size_groups": (14.3, 3.0),
    "ppe_sizes": (14.3, 4.7),
    "units": (14.3, 6.6),
}

TABLE_TITLES = {
    "departments": "departments · подразделения",
    "positions": "positions · должности",
    "users": "users · пользователи",
    "employees": "employees · сотрудники",
    "employee_ppe_sizes": "employee_ppe_sizes · размеры",
    "employee_ppe_issues": "employee_ppe_issues · выдачи СИЗ",
    "position_ppe_norms": "position_ppe_norms · нормы",
    "typical_norms": "typical_norms · пункты норм",
    "ppe_items": "ppe_items · наименования СИЗ",
    "ppe_functions": "ppe_functions · функции СИЗ",
    "ppe_size_groups": "ppe_size_groups · размерные группы",
    "ppe_sizes": "ppe_sizes · размеры (справочник)",
    "units": "units · единицы измерения",
    "alembic_version": "alembic_version · версия миграций",
}

TYPE_SHORT = {
    "integer": "int",
    "character varying": "varchar",
    "character": "char",
    "timestamp without time zone": "timestamp",
    "timestamp with time zone": "timestamptz",
    "double precision": "float8",
    "boolean": "bool",
}


@dataclass
class Column:
    name: str
    type: str
    not_null: bool
    pk: bool = False
    unique: bool = False
    fk: str | None = None


@dataclass
class Table:
    name: str
    columns: list[Column] = field(default_factory=list)

    @property
    def height(self) -> float:
        return HEADER_H + ROW_H * len(self.columns) + PAD_H


def psql(query: str) -> list[list[str]]:
    """Выгрузка из работающей базы: разделитель |, без заголовков и отступов."""
    result = subprocess.run(
        [
            "docker", "compose", "exec", "-T", "db",
            "psql", "-U", "ppe", "-d", "ppe_db", "-At", "-F", "|", "-c", query,
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=True,
    )
    return [line.split("|") for line in result.stdout.strip().splitlines() if line]


CONSTRAINTS_SQL = (
    "SELECT tc.table_name, tc.constraint_type, kcu.column_name "
    "FROM information_schema.table_constraints tc "
    "JOIN information_schema.key_column_usage kcu "
    "  ON kcu.constraint_name = tc.constraint_name "
    " AND kcu.table_schema = tc.table_schema "
    "WHERE tc.table_schema='public' "
    "  AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE')"
)

FOREIGN_KEYS_SQL = (
    "SELECT tc.table_name, kcu.column_name, ccu.table_name, ccu.column_name, "
    "rc.delete_rule FROM information_schema.table_constraints tc "
    "JOIN information_schema.key_column_usage kcu "
    "  ON kcu.constraint_name = tc.constraint_name "
    "JOIN information_schema.constraint_column_usage ccu "
    "  ON ccu.constraint_name = tc.constraint_name "
    "JOIN information_schema.referential_constraints rc "
    "  ON rc.constraint_name = tc.constraint_name "
    "WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='public'"
)


def fetch_schema() -> dict[str, Table]:
    tables: dict[str, Table] = {}

    for row in psql(
        "SELECT table_name, ordinal_position, column_name, data_type, "
        "character_maximum_length, is_nullable FROM information_schema.columns "
        "WHERE table_schema='public' ORDER BY table_name, ordinal_position"
    ):
        table_name, _pos, column_name, data_type, max_len, is_nullable = row
        short = TYPE_SHORT.get(data_type, data_type)
        if max_len:
            short = f"{short}({max_len})"
        tables.setdefault(table_name, Table(table_name)).columns.append(
            Column(name=column_name, type=short, not_null=is_nullable == "NO")
        )

    # Составные уникальные ключи отмечаем на каждом поле: иначе непонятно,
    # что ограничение общее (uq_employee_size_group, uq_size_group_size_gender)
    for row in psql(CONSTRAINTS_SQL):
        table_name, constraint_type, column_name = row
        for column in tables[table_name].columns:
            if column.name == column_name:
                if constraint_type == "PRIMARY KEY":
                    column.pk = True
                else:
                    column.unique = True

    for row in psql(FOREIGN_KEYS_SQL):
        table_name, column_name, ref_table, ref_column, delete_rule = row
        for column in tables[table_name].columns:
            if column.name == column_name:
                rule = "" if delete_rule == "NO ACTION" else f" {delete_rule}"
                column.fk = f"→ {ref_table}.{ref_column}{rule}"

    return tables


def fetch_relations() -> list[tuple[str, str, str, str]]:
    """Связи для линий: (дочерняя таблица, поле, родительская таблица, поле)."""
    return [(row[0], row[1], row[2], row[3]) for row in psql(FOREIGN_KEYS_SQL)]


# ---------------------------------------------------------------- XML страницы

def shape_id(value: int) -> str:
    return f"<Shape ID='{value}' Type='Shape' LineStyle='3' FillStyle='3' TextStyle='3'>"


def rect(shape_no: int, x: float, top: float, w: float, h: float, *,
         text: str, fill: str, line: str, text_color: str, size: float,
         align_h: int = 0, align_v: int = 0, bold: bool = False) -> str:
    """Прямоугольник с текстом. Координата top отсчитывается сверху страницы."""
    pin_y = PAGE_H - (top + h / 2)
    parts = [
        shape_id(shape_no),
        f"<Cell N='PinX' V='{x + w / 2:.4f}'/>",
        f"<Cell N='PinY' V='{pin_y:.4f}'/>",
        f"<Cell N='Width' V='{w:.4f}'/>",
        f"<Cell N='Height' V='{h:.4f}'/>",
        "<Cell N='LocPinX' V='0' F='Width*0.5'/>",
        "<Cell N='LocPinY' V='0' F='Height*0.5'/>",
        "<Cell N='Angle' V='0'/><Cell N='FlipX' V='0'/><Cell N='FlipY' V='0'/>",
        "<Cell N='ResizeMode' V='0'/>",
        f"<Cell N='FillForegnd' V='{fill}'/><Cell N='FillBkgnd' V='{fill}'/>",
        "<Cell N='FillPattern' V='1'/>",
        f"<Cell N='LineColor' V='{line}'/><Cell N='LineWeight' V='0.01'/>",
        "<Cell N='Rounding' V='0.03'/>",
        "<Cell N='LeftMargin' V='0.07'/><Cell N='RightMargin' V='0.04'/>",
        "<Cell N='TopMargin' V='0.03'/><Cell N='BottomMargin' V='0.02'/>",
        f"<Cell N='VerticalAlign' V='{align_v}'/>",
        "<Section N='Character'><Row IX='0'>",
        "<Cell N='Font' V='1'/>",
        f"<Cell N='Size' V='{size:.4f}'/>",
        f"<Cell N='Color' V='{text_color}'/>",
        f"<Cell N='Style' V='{1 if bold else 0}'/>",
        "</Row></Section>",
        "<Section N='Paragraph'><Row IX='0'>",
        f"<Cell N='HorzAlign' V='{align_h}'/>",
        "</Row></Section>",
        "<Section N='Geometry' IX='0'>",
        "<Cell N='NoFill' V='0'/><Cell N='NoLine' V='0'/><Cell N='NoShow' V='0'/>",
        "<Cell N='NoSnap' V='0'/><Cell N='NoQuickDrag' V='0'/>",
        "<Row T='RelMoveTo' IX='1'><Cell N='X' V='0'/><Cell N='Y' V='0'/></Row>",
        "<Row T='RelLineTo' IX='2'><Cell N='X' V='1'/><Cell N='Y' V='0'/></Row>",
        "<Row T='RelLineTo' IX='3'><Cell N='X' V='1'/><Cell N='Y' V='1'/></Row>",
        "<Row T='RelLineTo' IX='4'><Cell N='X' V='0'/><Cell N='Y' V='1'/></Row>",
        "<Row T='RelLineTo' IX='5'><Cell N='X' V='0'/><Cell N='Y' V='0'/></Row>",
        "</Section>",
        f"<Text>{escape(text)}</Text>",
        "</Shape>",
    ]
    return "".join(parts)


def column_line(column: Column) -> str:
    """Строка поля для тела таблицы: имя, тип, ключи, ссылка."""
    flags = []
    if column.pk:
        flags.append("PK")
    if column.unique:
        flags.append("U")
    if column.not_null and not column.pk:
        flags.append("NN")

    tail = f"  {column.fk}" if column.fk else ""
    return f"{column.name:<23}{column.type:<13}{' '.join(flags):<7}{tail}"


def build_page(tables: dict[str, Table], relations: list[tuple[str, str, str, str]]) -> str:
    shapes: list[str] = []
    sid = 1

    # Заголовок и легенда
    shapes.append(rect(
        sid, 0.5, 0.30, 9.0, 0.40,
        text="PPE Tracker — схема базы данных",
        fill=BRAND, line=BRAND, text_color="#FFFFFF", size=0.20,
        align_h=0, align_v=1, bold=True,
    ))
    sid += 1
    shapes.append(rect(
        sid, 0.5, 0.72, 9.0, 0.30,
        text=(
            f"PostgreSQL 16 · таблиц: {len(tables)} · связей: {len(relations)} · "
            f"сгенерировано из information_schema {date.today().strftime('%d.%m.%Y')}"
        ),
        fill="#FFFFFF", line="#FFFFFF", text_color=INK, size=0.11, align_h=0,
    ))
    sid += 1
    shapes.append(rect(
        sid, 10.2, 0.30, 8.7, 0.72,
        text=(
            "PK — первичный ключ, U — уникальное поле, NN — NOT NULL\n"
            "→ — внешний ключ; в скобках правило ON DELETE\n"
            "Линии идут от дочерней таблицы к родительской (стрелка — к родителю)"
        ),
        fill="#FFFFFF", line=LINE, text_color=INK, size=0.10, align_h=0,
    ))
    sid += 1

    # Таблицы: отдельная фигура-заголовок и фигура-тело
    boxes: dict[str, tuple[float, float, float, float]] = {}
    for name, table in tables.items():
        x, top = LAYOUT[name]
        height = table.height
        title = TABLE_TITLES.get(name, name)

        shapes.append(rect(
            sid, x, top, BOX_W, HEADER_H,
            text=title, fill=BRAND, line=BRAND, text_color="#FFFFFF",
            size=0.105, align_h=1, align_v=1, bold=True,
        ))
        sid += 1

        body_top = top + HEADER_H
        body_h = height - HEADER_H
        body_text = "\n".join(column_line(c) for c in table.columns)
        shapes.append(rect(
            sid, x, body_top, BOX_W, body_h,
            text=body_text, fill="#FFFFFF", line=LINE, text_color=INK,
            size=0.09, align_h=0, align_v=0,
        ))
        sid += 1

        boxes[name] = (x, top, BOX_W, height)

    # Связи: линия от границы дочерней фигуры к границе родительской
    for child, _child_col, parent, _parent_col in relations:
        cx, ctop, cw, ch = boxes[child]
        px, ptop, pw, ph = boxes[parent]

        c_mid = ctop + ch / 2
        p_mid = ptop + ph / 2

        if px >= cx + cw:
            start = (cx + cw, c_mid)
            end = (px, p_mid)
        elif px + pw <= cx:
            start = (cx, c_mid)
            end = (px + pw, p_mid)
        elif ptop >= ctop:
            start = (cx + cw / 2, ctop + ch)
            end = (px + pw / 2, ptop)
        else:
            start = (cx + cw / 2, ctop)
            end = (px + pw / 2, ptop + ph)

        x1, y1 = start[0], PAGE_H - start[1]
        x2, y2 = end[0], PAGE_H - end[1]
        shapes.append(connector(sid, x1, y1, x2, y2))
        sid += 1

    body = "".join(shapes)
    return (
        "<?xml version='1.0' encoding='utf-8' ?>"
        "<PageContents xmlns='http://schemas.microsoft.com/office/visio/2012/main' "
        "xmlns:r='http://schemas.openxmlformats.org/officeDocument/2006/relationships' "
        "xml:space='preserve'><Shapes>" + body + "</Shapes></PageContents>"
    )



def connector(shape_no: int, x1: float, y1: float, x2: float, y2: float) -> str:
    """Линия связи. Координаты — уже в системе Visio (Y снизу вверх)."""
    length = ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5
    angle = math.atan2(y2 - y1, x2 - x1)
    parts = [
        shape_id(shape_no),
        f"<Cell N='PinX' V='{(x1 + x2) / 2:.4f}'/>",
        f"<Cell N='PinY' V='{(y1 + y2) / 2:.4f}'/>",
        f"<Cell N='Width' V='{length:.4f}'/>",
        "<Cell N='Height' V='0'/>",
        f"<Cell N='LocPinX' V='{length / 2:.4f}' F='Width*0.5'/>",
        "<Cell N='LocPinY' V='0'/>",
        f"<Cell N='Angle' V='{angle:.6f}'/>",
        "<Cell N='FlipX' V='0'/><Cell N='FlipY' V='0'/><Cell N='ResizeMode' V='0'/>",
        f"<Cell N='BeginX' V='{x1:.4f}'/><Cell N='BeginY' V='{y1:.4f}'/>",
        f"<Cell N='EndX' V='{x2:.4f}'/><Cell N='EndY' V='{y2:.4f}'/>",
        f"<Cell N='LineColor' V='{ACCENT}'/><Cell N='LineWeight' V='0.015'/>",
        "<Cell N='EndArrow' V='4'/><Cell N='EndArrowSize' V='1'/>",
        "<Section N='Geometry' IX='0'>",
        "<Cell N='NoFill' V='1'/><Cell N='NoLine' V='0'/><Cell N='NoShow' V='0'/>",
        "<Cell N='NoSnap' V='0'/><Cell N='NoQuickDrag' V='0'/>",
        "<Row T='MoveTo' IX='1'><Cell N='X' V='0' F='Width*0'/></Row>",
        f"<Row T='LineTo' IX='2'><Cell N='X' V='{length:.4f}' F='Width*1'/><Cell N='Y' V='0'/></Row>",
        "</Section>",
        "</Shape>",
    ]
    return "".join(parts)


# ---------------------------------------------------------------- сборка .vsdx

def build_mermaid(tables: dict[str, Table], relations: list[tuple[str, str, str, str]]) -> str:
    """Текстовое представление схемы: видно в браузере и диффится в git."""
    lines = [
        "# Схема базы данных PPE Tracker",
        "",
        "Диаграмма Visio: `docs/ppe-tracker-db-schema.vsdx`.",
        "Перегенерация (обе схемы сразу): `.venv/bin/python docs/make_er_diagram.py`",
        "",
        "```mermaid",
        "erDiagram",
    ]

    for child, child_col, parent, _parent_col in sorted(relations, key=lambda r: (r[2], r[0])):
        lines.append(f'    {parent} ||--o{{ {child} : "{child_col}"')

    for name, table in tables.items():
        lines.append(f"    {name} {{")
        for column in table.columns:
            kind = column.type.split("(")[0]
            flags = []
            if column.pk:
                flags.append("PK")
            if column.fk:
                flags.append("FK")
            if column.unique:
                flags.append("UK")
            suffix = f" \"{','.join(flags)}\"" if flags else ""
            lines.append(f"        {kind} {column.name}{suffix}")
        lines.append("    }")

    lines += ["```", ""]
    return "\n".join(lines)


def build_package(page_xml: str) -> None:
    """Собирает .vsdx: каркас Visio + наша страница и размер листа."""
    with zipfile.ZipFile(TEMPLATE) as template, zipfile.ZipFile(
        OUTPUT, "w", zipfile.ZIP_DEFLATED
    ) as out:
        for item in template.infolist():
            data = template.read(item.filename)

            if item.filename == "visio/pages/page1.xml":
                data = page_xml.encode("utf-8")

            elif item.filename == "visio/pages/pages.xml":
                text = data.decode("utf-8")
                text = text.replace(
                    "NameU='Page-1' Name='Page-1'",
                    f"NameU='{PAGE_NAME}' Name='{PAGE_NAME}'",
                )
                text = re.sub(
                    r"<Cell N='PageWidth' V='[^']*'",
                    f"<Cell N='PageWidth' V='{PAGE_W}'",
                    text,
                )
                text = re.sub(
                    r"<Cell N='PageHeight' V='[^']*'",
                    f"<Cell N='PageHeight' V='{PAGE_H}'",
                    text,
                )
                text = re.sub(r"ViewCenterX='[^']*'", f"ViewCenterX='{PAGE_W / 2}'", text)
                text = re.sub(r"ViewCenterY='[^']*'", f"ViewCenterY='{PAGE_H / 2}'", text)
                data = text.encode("utf-8")

            elif item.filename == "visio/document.xml":
                # Моноширинный шрифт нужен, чтобы колонки полей не «плясали»:
                # в документе объявлен только Calibri, добавляем Consolas (индекс 1)
                text = data.decode("utf-8")
                if "NameU='Consolas'" not in text:
                    text = text.replace(
                        "<FaceName NameU='Calibri'",
                        "<FaceName NameU='Consolas' UnicodeRanges='-2147483648 8 0' "
                        "CharSets='536871423 0' Panose='2 11 6 9 2 2 2 4 2 4' Flags='325'/>"
                        "<FaceName NameU='Calibri'",
                    )
                data = text.encode("utf-8")

            elif item.filename == "docProps/app.xml":
                # Каркас помнит три страницы: после чистки осталась одна
                text = data.decode("utf-8")
                text = text.replace("<vt:i4>3</vt:i4>", "<vt:i4>1</vt:i4>")
                text = re.sub(
                    r"<TitlesOfParts>.*</TitlesOfParts>",
                    "<TitlesOfParts><vt:vector size='1' baseType='lpstr'>"
                    f"<vt:lpstr>{PAGE_NAME}</vt:lpstr></vt:vector></TitlesOfParts>",
                    text,
                    flags=re.S,
                )
                data = text.encode("utf-8")

            elif item.filename == "docProps/core.xml":
                # Автор и дата каркаса не должны оставаться в нашем файле
                text = data.decode("utf-8")
                text = re.sub(r"<dc:title>.*?</dc:title>", f"<dc:title>{PAGE_NAME}</dc:title>", text)
                text = re.sub(
                    r"<dc:subject>.*?</dc:subject>",
                    "<dc:subject>PostgreSQL 16, схема базы данных PPE Tracker</dc:subject>",
                    text,
                )
                text = text.replace("<dc:creator>Dave Howard</dc:creator>", "<dc:creator>PPE Tracker</dc:creator>")
                text = text.replace(
                    "<cp:lastModifiedBy>Dave Howard</cp:lastModifiedBy>",
                    "<cp:lastModifiedBy>PPE Tracker</cp:lastModifiedBy>",
                )
                text = re.sub(r"<dc:language>.*?</dc:language>", "<dc:language>ru-RU</dc:language>", text)
                today = f"{date.today().isoformat()}T00:00:00Z"
                text = re.sub(
                    r"(<dcterms:created[^>]*>).*?(</dcterms:created>)", rf"\g<1>{today}\g<2>", text
                )
                text = re.sub(
                    r"(<dcterms:modified[^>]*>).*?(</dcterms:modified>)", rf"\g<1>{today}\g<2>", text
                )
                data = text.encode("utf-8")

            out.writestr(item, data)


def main() -> int:
    tables = fetch_schema()
    relations = fetch_relations()

    unknown = [name for name in tables if name not in LAYOUT]
    if unknown:
        print(
            "Новые таблицы без места на схеме: " + ", ".join(sorted(unknown)),
            "\nДобавьте их в LAYOUT (и, при желании, в TABLE_TITLES) и запустите снова.",
        )
        return 1

    page_xml = build_page(tables, relations)

    # Проверяем XML до записи файла: битая разметка в Visio не откроется
    ET.fromstring(page_xml)

    build_package(page_xml)

    with open(MERMAID, "w", encoding="utf-8") as mermaid_file:
        mermaid_file.write(build_mermaid(tables, relations))

    with zipfile.ZipFile(OUTPUT) as result:
        shapes = ET.fromstring(result.read("visio/pages/page1.xml")).findall(
            ".//{http://schemas.microsoft.com/office/visio/2012/main}Shape"
        )

    print(
        f"{OUTPUT}: таблиц {len(tables)}, связей {len(relations)}, фигур {len(shapes)}"
    )
    print(f"{MERMAID}: та же схема текстом (mermaid) для просмотра в браузере")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

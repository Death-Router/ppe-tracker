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
PDF = f"{PROJECT_ROOT}/docs/ppe-tracker-db-schema.pdf"
PAGE_NAME = "Схема БД"

# Размер страницы и геометрия таблиц (дюймы — единица Visio по умолчанию)
PAGE_W = 20.6
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
    "employees": (5.5, 1.5),
    "employee_ppe_sizes": (5.5, 5.2),
    "employee_ppe_issues": (5.5, 6.9),
    "position_ppe_norms": (10.5, 1.5),
    "typical_norms": (10.5, 4.0),
    "ppe_items": (10.5, 5.7),
    "ppe_functions": (15.5, 1.5),
    "ppe_size_groups": (15.5, 3.0),
    "ppe_sizes": (15.5, 4.7),
    "units": (15.5, 6.6),
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
        f"<Cell N='LocPinX' V='{w / 2:.4f}' F='Width*0.5'/>",
        f"<Cell N='LocPinY' V='{h / 2:.4f}' F='Height*0.5'/>",
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
    """Связь как коннектор Visio на мастере Dynamic connector.

    Ключевые моменты, без которых Visio рисует линии «из ниоткуда»:
    * фигура обязана ссылаться на мастер (Master='2'), иначе у неё нет формул
      1D-фигуры, и Visio трактует её как обычный прямоугольник;
    * Width/Height у Visio неотрицательные, а направление задаётся FlipX/FlipY —
      поэтому берём модули, а знаки уводим в флаги.
    """
    flip_x = 1 if x2 < x1 else 0
    flip_y = 1 if y2 < y1 else 0
    width = abs(x2 - x1)
    height = abs(y2 - y1)
    mid_x = (x1 + x2) / 2
    mid_y = (y1 + y2) / 2
    return (
        f"<Shape ID='{shape_no}' NameU='Dynamic connector' Name='Dynamic connector' "
        "Type='Shape' Master='2'>"
        f"<Cell N='PinX' V='{mid_x:.4f}' F='Inh'/>"
        f"<Cell N='PinY' V='{mid_y:.4f}' F='Inh'/>"
        f"<Cell N='Width' V='{width:.4f}'/>"
        f"<Cell N='Height' V='{height:.4f}'/>"
        f"<Cell N='LocPinX' V='{width / 2:.4f}' F='Inh'/>"
        f"<Cell N='LocPinY' V='{height / 2:.4f}' F='Inh'/>"
        f"<Cell N='FlipX' V='{flip_x}'/><Cell N='FlipY' V='{flip_y}'/>"
        f"<Cell N='BeginX' V='{x1:.4f}'/><Cell N='BeginY' V='{y1:.4f}'/>"
        f"<Cell N='EndX' V='{x2:.4f}'/><Cell N='EndY' V='{y2:.4f}'/>"
        "<Cell N='LayerMember' V='0'/>"
        "<Cell N='BegTrigger' V='1' F='_XFTRIGGER(EventXFMod)'/>"
        "<Cell N='EndTrigger' V='1' F='_XFTRIGGER(EventXFMod)'/>"
        "<Cell N='ShapeRouteStyle' V='16'/><Cell N='ConLineRouteExt' V='1'/>"
        f"<Cell N='TxtPinX' V='{mid_x:.4f}' F='Inh'/>"
        f"<Cell N='TxtPinY' V='{mid_y:.4f}' F='Inh'/>"
        "<Cell N='TxtHeight' V='0.2445' F='Inh'/>"
        "<Cell N='TxtLocPinY' V='0.1222' F='Inh'/>"
        f"<Cell N='LineColor' V='{ACCENT}'/><Cell N='LineWeight' V='0.015'/>"
        "<Cell N='BeginArrow' V='0'/><Cell N='EndArrow' V='4'/>"
        "<Cell N='EndArrowSize' V='1'/>"
        "<Section N='Control'><Row N='TextPosition'>"
        f"<Cell N='X' V='{mid_x:.4f}'/><Cell N='Y' V='{mid_y:.4f}'/>"
        f"<Cell N='XDyn' V='{mid_x:.4f}' F='Inh'/>"
        f"<Cell N='YDyn' V='{mid_y:.4f}' F='Inh'/>"
        "<Cell N='XCon' V='0' F='Inh'/></Row></Section>"
        "<Section N='Geometry' IX='0'>"
        f"<Row T='LineTo' IX='2'><Cell N='X' V='{width:.4f}'/>"
        f"<Cell N='Y' V='{height:.4f}'/></Row>"
        "<Row T='LineTo' IX='3' Del='1'/></Section>"
        "</Shape>"
    )

# ---------------------------------------------------------------- PDF-схема

# Visio в этой среде нет, поэтому основной человекочитаемый вид — PDF:
# координаты задаём сами, рендер предсказуем. Шрифты DejaVu — с кириллицей.
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FONTS = {
    "text": f"{FONT_DIR}/DejaVuSans.ttf",
    "bold": f"{FONT_DIR}/DejaVuSans-Bold.ttf",
    "mono": f"{FONT_DIR}/DejaVuSansMono.ttf",
}

# Геометрия PDF (дюймы). Независима от Visio-раскладки выше.
PDF_BOX_W = 5.6
PDF_HEADER_H = 0.44
PDF_ROW_H = 0.25
PDF_PAD_H = 0.06
PDF_GUTTER = 1.1        # жёлоб между колонками: в нём идут шины связей
PDF_MARGIN_X = 1.1      # левое/правое поле: тоже жёлоб для связей внутри колонки
PDF_TOP = 1.85
PDF_TABLE_GAP = 0.45
PDF_BOTTOM = 0.5

# Колонки слева направо; внутри колонки таблицы идут сверху вниз.
# Связь допускается только между соседними колонками или внутри одной.
PDF_COLUMNS: list[list[str]] = [
    ["users", "departments", "positions", "alembic_version"],
    ["employees", "position_ppe_norms", "typical_norms"],
    ["employee_ppe_sizes", "employee_ppe_issues", "ppe_items"],
    ["ppe_size_groups", "ppe_sizes", "ppe_functions", "units"],
]

# Смысловые группы: цвет шапки таблицы
PDF_GROUPS: list[tuple[str, str, list[str]]] = [
    ("Организация и доступ", "#5B2C8A", ["users", "departments", "positions"]),
    ("Сотрудники и выдачи", "#1F5FA8",
     ["employees", "employee_ppe_sizes", "employee_ppe_issues"]),
    ("Нормы", "#0E7C7B", ["position_ppe_norms", "typical_norms"]),
    ("Справочники СИЗ", "#B25E09",
     ["ppe_items", "ppe_functions", "ppe_size_groups", "ppe_sizes", "units"]),
    ("Служебные", "#6B7280", ["alembic_version"]),
]

# Цвет линии связи задаёт родительская таблица: все связи к ней одного цвета
LINK_COLORS = ["#E4572E", "#2E86AB", "#2FA36B", "#9B5DE5",
               "#E09F1F", "#D81B60", "#00897B", "#7A5C45"]

PAGE_BG = "#F5F4F9"
MUTED = "#6B6880"
BAND = "#F6F4FA"


def register_fonts() -> None:
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    for name, path in FONTS.items():
        pdfmetrics.registerFont(TTFont(name, path))


Box = tuple[float, float, float, float]  # лево, верх, ширина, высота (дюймы сверху)


def pdf_table_height(table: Table) -> float:
    return PDF_HEADER_H + PDF_PAD_H * 2 + PDF_ROW_H * len(table.columns)


def pdf_row_y(box: Box, index: int) -> float:
    """Вертикальный центр строки поля (дюймы сверху)."""
    return box[1] + PDF_HEADER_H + PDF_PAD_H + (index + 0.5) * PDF_ROW_H


def pdf_layout(tables: dict[str, Table]):
    """Прямоугольники таблиц, номер колонки, x колонок, размер страницы."""
    placed = [name for column in PDF_COLUMNS for name in column]
    missing = sorted(set(tables) - set(placed))
    if missing:
        raise ValueError(
            "Таблицы без места в PDF_COLUMNS: " + ", ".join(missing)
        )

    col_x = [PDF_MARGIN_X + i * (PDF_BOX_W + PDF_GUTTER) for i in range(len(PDF_COLUMNS))]
    page_w = col_x[-1] + PDF_BOX_W + PDF_MARGIN_X

    boxes: dict[str, Box] = {}
    col_of: dict[str, int] = {}
    bottom = 0.0
    for index, names in enumerate(PDF_COLUMNS):
        top = PDF_TOP
        for name in names:
            if name not in tables:
                continue
            height = pdf_table_height(tables[name])
            boxes[name] = (col_x[index], top, PDF_BOX_W, height)
            col_of[name] = index
            top += height + PDF_TABLE_GAP
        bottom = max(bottom, top - PDF_TABLE_GAP)
    return boxes, col_of, col_x, page_w, bottom + PDF_BOTTOM


@dataclass
class PdfLink:
    child: str
    parent: str
    optional: bool          # FK допускает NULL: у родителя рисуем «кружок»
    yc: float               # строка FK у дочерней таблицы
    yp: float               # строка PK у родительской
    xc: float               # край дочерней таблицы, откуда выходит линия
    xp: float               # край родительской таблицы, куда входит линия
    c_dir: int              # +1: линия уходит вправо от края, -1: влево
    p_dir: int
    gutter: int             # номер жёлоба: 0 — левое поле, n — правое
    bus: float = 0.0        # x вертикального участка
    color: str = "#000000"

    @property
    def points(self) -> list[tuple[float, float]]:
        return [(self.xc, self.yc), (self.bus, self.yc),
                (self.bus, self.yp), (self.xp, self.yp)]


def route_links(
    tables: dict[str, Table],
    relations: list[tuple[str, str, str, str]],
    boxes: dict[str, Box],
    col_of: dict[str, int],
    col_x: list[float],
    page_w: float,
) -> list[PdfLink]:
    """Ортогональные маршруты: от строки FK до строки PK по шине в жёлобе.

    Линия не заходит на таблицы: горизонтали лежат в жёлобе между колонками,
    вертикаль — на своей «шине». Порядок шин в жёлобе подбирается перебором
    так, чтобы число пересечений было минимальным.
    """
    from itertools import permutations

    parents = sorted({parent for _c, _cc, parent, _pc in relations})
    color_of = {name: LINK_COLORS[i % len(LINK_COLORS)] for i, name in enumerate(parents)}

    links: list[PdfLink] = []
    attach: list[tuple[str, str]] = []  # у какого края жёлоба «растёт» горизонталь
    for child, child_col, parent, parent_col in relations:
        ci, pi = col_of[child], col_of[parent]
        if abs(ci - pi) > 1:
            raise ValueError(
                f"Связь {child} → {parent} идёт через колонку: переставьте таблицы "
                "в PDF_COLUMNS, чтобы связанные таблицы были рядом."
            )
        cbox, pbox = boxes[child], boxes[parent]
        names_c = [c.name for c in tables[child].columns]
        names_p = [c.name for c in tables[parent].columns]
        yc = pdf_row_y(cbox, names_c.index(child_col))
        yp = pdf_row_y(pbox, names_p.index(parent_col))
        optional = not tables[child].columns[names_c.index(child_col)].not_null

        if ci == pi:
            if ci == 0:     # внутри первой колонки — по левому полю
                xc, xp, c_dir, p_dir, gutter = cbox[0], pbox[0], -1, -1, 0
                sides = ("hi", "hi")
            else:           # иначе по жёлобу справа
                xc, xp = cbox[0] + cbox[2], pbox[0] + pbox[2]
                c_dir, p_dir, gutter = 1, 1, ci + 1
                sides = ("lo", "lo")
        elif pi > ci:
            xc, xp, c_dir, p_dir, gutter = cbox[0] + cbox[2], pbox[0], 1, -1, pi
            sides = ("lo", "hi")
        else:
            xc, xp, c_dir, p_dir, gutter = cbox[0], pbox[0] + pbox[2], -1, 1, ci
            sides = ("hi", "lo")

        links.append(PdfLink(child, parent, optional, yc, yp, xc, xp,
                             c_dir, p_dir, gutter, color=color_of[parent]))
        attach.append(sides)

    n = len(col_x)

    def bounds(j: int) -> tuple[float, float]:
        lo = 0.25 if j == 0 else col_x[j - 1] + PDF_BOX_W
        hi = col_x[0] if j == 0 else (page_w - 0.25 if j == n else col_x[j])
        return lo, hi

    for j in range(n + 1):
        members = [i for i, link in enumerate(links) if link.gutter == j]
        if not members:
            continue
        lo, hi = bounds(j)
        members.sort(key=lambda i: (links[i].yc + links[i].yp) / 2)

        def cost(order: tuple[int, ...]) -> int:
            count = len(order)
            xs = {idx: lo + (hi - lo) * (rank + 1) / (count + 1)
                  for rank, idx in enumerate(order)}
            total = 0
            for a in order:
                top, bottom = sorted((links[a].yc, links[a].yp))
                for b in order:
                    if a == b or links[a].parent == links[b].parent:
                        continue
                    for y, side in ((links[b].yc, attach[b][0]),
                                    (links[b].yp, attach[b][1])):
                        edge = lo if side == "lo" else hi
                        left, right = sorted((edge, xs[b]))
                        if top < y < bottom and left < xs[a] < right:
                            total += 1
            return total

        if len(members) <= 7:
            best = min(permutations(members), key=cost)
        else:
            best = tuple(members)
        for rank, idx in enumerate(best):
            links[idx].bus = lo + (hi - lo) * (rank + 1) / (len(best) + 1)
    return links


def build_pdf(tables: dict[str, Table], relations: list[tuple[str, str, str, str]]) -> None:
    """Рисует схему в PDF: фон, связи, таблицы, заголовок и легенду."""
    from reportlab.lib.colors import HexColor
    from reportlab.pdfbase.pdfmetrics import stringWidth
    from reportlab.pdfgen import canvas

    register_fonts()
    boxes, col_of, col_x, page_w, page_h = pdf_layout(tables)
    links = route_links(tables, relations, boxes, col_of, col_x, page_w)

    pdf = canvas.Canvas(PDF, pagesize=(page_w * 72, page_h * 72))
    pdf.setTitle("PPE Tracker — схема базы данных")
    pdf.setAuthor("PPE Tracker")

    def Y(top: float) -> float:
        return (page_h - top) * 72

    def X(x: float) -> float:
        return x * 72

    group_of = {name: (title, color) for title, color, names in PDF_GROUPS for name in names}

    def fill(color: str) -> None:
        pdf.setFillColor(HexColor(color))

    def stroke(color: str) -> None:
        pdf.setStrokeColor(HexColor(color))

    def text(x: float, y_center: float, value: str, font: str, size: float,
             color: str, align: str = "left") -> None:
        pdf.setFont(font, size)
        fill(color)
        baseline = Y(y_center) - size * 0.34
        if align == "right":
            pdf.drawRightString(X(x), baseline, value)
        elif align == "center":
            pdf.drawCentredString(X(x), baseline, value)
        else:
            pdf.drawString(X(x), baseline, value)

    def badge(x: float, y_center: float, label: str, color: str, width: float = 0.3) -> None:
        fill(color)
        pdf.roundRect(X(x), Y(y_center) - 6.2, width * 72, 12.4, 3, stroke=0, fill=1)
        text(x + width / 2, y_center, label, "bold", 7.2, "#FFFFFF", "center")

    # --- фон -----------------------------------------------------------
    fill(PAGE_BG)
    pdf.rect(0, 0, page_w * 72, page_h * 72, stroke=0, fill=1)

    # --- маркеры связей: «много» у дочерней, «один» у родительской ------------
    def many_marker(x: float, y_: float, direction: int) -> None:
        tip = x + direction * 0.16
        pdf.line(X(tip), Y(y_), X(x), Y(y_ - 0.085))
        pdf.line(X(tip), Y(y_), X(x), Y(y_ + 0.085))

    def one_marker(x: float, y_: float, direction: int, optional: bool) -> None:
        bar = x + direction * 0.11
        pdf.line(X(bar), Y(y_ - 0.085), X(bar), Y(y_ + 0.085))
        if optional:
            cx = x + direction * 0.25
            fill(PAGE_BG)
            pdf.circle(X(cx), Y(y_), 3.2, stroke=1, fill=1)

    # --- 1. связи ------------------------------------------------------------
    # Белое «окаймление» под линиями: на пересечении верхняя линия как бы
    # перекрывает нижнюю. Окаймление рисуем группами по родителю, чтобы
    # линии одной группы (общий «ствол» у родителя) не разрезали друг друга.
    by_parent: dict[str, list[PdfLink]] = {}
    for link in links:
        by_parent.setdefault(link.parent, []).append(link)

    def path_of(link: PdfLink):
        path = pdf.beginPath()
        pts = link.points
        path.moveTo(X(pts[0][0]), Y(pts[0][1]))
        for px, py in pts[1:]:
            path.lineTo(X(px), Y(py))
        return path

    pdf.setLineJoin(1)
    pdf.setLineCap(0)
    for group in by_parent.values():
        stroke(PAGE_BG)
        pdf.setLineWidth(4.2)
        for link in group:
            pdf.drawPath(path_of(link), stroke=1, fill=0)
        for link in group:
            stroke(link.color)
            pdf.setLineWidth(1.5)
            pdf.drawPath(path_of(link), stroke=1, fill=0)
            pdf.setLineWidth(1.3)
            many_marker(link.xc, link.yc, link.c_dir)
            one_marker(link.xp, link.yp, link.p_dir, link.optional)

    # Диагностика: пересечения допустимы, наложения линий — нет
    segments = [(link.parent, a, b) for link in links
                for a, b in zip(link.points, link.points[1:], strict=False)]
    crossings = overlaps = 0
    for i, (pa, a1, a2) in enumerate(segments):
        for pb, b1, b2 in segments[i + 1:]:
            if pa == pb:
                continue
            a_h, b_h = abs(a1[1] - a2[1]) < 1e-9, abs(b1[1] - b2[1]) < 1e-9
            if a_h != b_h:
                h = (a1, a2) if a_h else (b1, b2)
                v = (b1, b2) if a_h else (a1, a2)
                hx = sorted((h[0][0], h[1][0]))
                vy = sorted((v[0][1], v[1][1]))
                if hx[0] < v[0][0] < hx[1] and vy[0] < h[0][1] < vy[1]:
                    crossings += 1
            elif a_h and abs(a1[1] - b1[1]) < 0.01:
                lo_a, hi_a = sorted((a1[0], a2[0]))
                lo_b, hi_b = sorted((b1[0], b2[0]))
                if min(hi_a, hi_b) - max(lo_a, lo_b) > 0.02:
                    overlaps += 1
            elif not a_h and abs(a1[0] - b1[0]) < 0.01:
                lo_a, hi_a = sorted((a1[1], a2[1]))
                lo_b, hi_b = sorted((b1[1], b2[1]))
                if min(hi_a, hi_b) - max(lo_a, lo_b) > 0.02:
                    overlaps += 1
    print(f"  связей: {len(links)} · пересечений: {crossings} · наложений: {overlaps}")
    if overlaps:
        print("  ВНИМАНИЕ: линии разных связей накладываются — поправьте PDF_COLUMNS")

    # --- 2. таблицы -------------------------------------------------------------
    fk_targets = {(link.child, c.name) for link in links
                  for c in tables[link.child].columns if False}  # (заполнено ниже)
    del fk_targets

    for name, (left, top, width, height) in boxes.items():
        table = tables[name]
        _title, color = group_of.get(name, ("", "#6B7280"))

        fill("#DDD9E8")  # лёгкая тень
        pdf.roundRect(X(left + 0.04), Y(top + height + 0.04), width * 72, height * 72,
                      5, stroke=0, fill=1)
        fill("#FFFFFF")
        stroke(color)
        pdf.setLineWidth(1.0)
        pdf.roundRect(X(left), Y(top + height), width * 72, height * 72, 5, stroke=1, fill=1)

        # зебра по строкам
        for index in range(len(table.columns)):
            if index % 2 == 1:
                fill(BAND)
                row_top = top + PDF_HEADER_H + PDF_PAD_H + index * PDF_ROW_H
                pdf.rect(X(left + 0.012), Y(row_top + PDF_ROW_H), (width - 0.024) * 72,
                         PDF_ROW_H * 72, stroke=0, fill=1)

        # шапка
        fill(color)
        pdf.roundRect(X(left), Y(top + PDF_HEADER_H), width * 72, PDF_HEADER_H * 72,
                      5, stroke=0, fill=1)
        pdf.rect(X(left), Y(top + PDF_HEADER_H), width * 72, PDF_HEADER_H * 36,
                 stroke=0, fill=1)
        english, _sep, russian = TABLE_TITLES.get(name, name).partition(" · ")
        text(left + 0.14, top + PDF_HEADER_H / 2, english, "bold", 11, "#FFFFFF")
        if russian:
            text(left + width - 0.14, top + PDF_HEADER_H / 2, russian, "text", 8.6,
                 "#E9E4F5", "right")

        # строки полей
        for index, column in enumerate(table.columns):
            yc = pdf_row_y((left, top, width, height), index)
            text(left + 0.14, yc, column.name, "bold" if column.pk else "text", 8.8, INK)
            text(left + 1.85, yc, column.type, "mono", 7.8, MUTED)

            bx = left + 2.62
            marks = []
            if column.pk:
                marks.append(("PK", BRAND))
            if column.fk:
                marks.append(("FK", "#1F5FA8"))
            if column.unique:
                marks.append(("U", "#2FA36B"))
            for label, badge_color in marks:
                badge(bx, yc, label, badge_color, 0.28 if len(label) == 2 else 0.22)
                bx += 0.32 if len(label) == 2 else 0.26
            if column.not_null and not column.pk:
                text(left + 3.38, yc, "NN", "text", 7, "#8A86A0")

            if column.fk:
                target = column.fk.removeprefix("→ ")
                reference, _s, rule = target.partition(" ")
                label = f"→ {reference.split('.')[0]}"
                text(left + 3.7, yc, label, "text", 7.4, "#1F5FA8")
                if rule:
                    # Правило ставим вплотную к названию, а не к краю: иначе налезает
                    label_w = stringWidth(label, "text", 7.4) / 72
                    text(left + 3.7 + label_w + 0.1, yc, rule, "text", 6.2, "#9A3B3B")

    # --- 3. заголовок ----------------------------------------------------------
    fill(BRAND)
    pdf.roundRect(X(PDF_MARGIN_X), Y(1.0), 9.2 * 72, 0.68 * 72, 6, stroke=0, fill=1)
    text(PDF_MARGIN_X + 0.3, 0.66, "PPE Tracker — схема базы данных", "bold", 21, "#FFFFFF")
    text(PDF_MARGIN_X, 1.28,
         f"PostgreSQL 16 · таблиц: {len(tables)} · связей: {len(relations)} · "
         f"сгенерировано из information_schema {date.today().strftime('%d.%m.%Y')}",
         "text", 9, MUTED)

    # --- 4. легенда -------------------------------------------------------------
    lg_w, lg_h = 13.4, 1.4
    lg_left = page_w - PDF_MARGIN_X - lg_w
    lg_top = 0.32
    fill("#FFFFFF")
    stroke(LINE)
    pdf.setLineWidth(0.8)
    pdf.roundRect(X(lg_left), Y(lg_top + lg_h), lg_w * 72, lg_h * 72, 6, stroke=1, fill=1)

    # группы таблиц
    gx, gy = lg_left + 0.25, lg_top + 0.24
    for title, color, _names in PDF_GROUPS:
        fill(color)
        pdf.roundRect(X(gx), Y(gy) - 4.5, 0.3 * 72, 9, 2.5, stroke=0, fill=1)
        text(gx + 0.42, gy, title, "text", 8.6, INK)
        gy += 0.235

    # обозначения полей
    kx = lg_left + 3.55
    ky = lg_top + 0.24
    for label, color, caption in (
        ("PK", BRAND, "первичный ключ"),
        ("FK", "#1F5FA8", "внешний ключ; справа — таблица и правило ON DELETE"),
        ("U", "#2FA36B", "уникальное значение"),
    ):
        badge(kx, ky, label, color, 0.28 if len(label) == 2 else 0.22)
        text(kx + 0.42, ky, caption, "text", 8.6, INK)
        ky += 0.235
    text(kx, ky, "NN", "text", 7.6, "#8A86A0")
    text(kx + 0.42, ky, "NOT NULL (без отметки — поле допускает NULL)", "text", 8.6, INK)

    # обозначения связей
    sx = lg_left + 8.4
    sy = lg_top + 0.24
    stroke("#555555")
    pdf.setLineWidth(1.3)
    for kind, caption in (
        ("many", "конец «вилкой» — дочерняя таблица (поле FK)"),
        ("one", "черта — родительская таблица (поле PK)"),
        ("opt", "кружок — связь необязательна (FK допускает NULL)"),
    ):
        pdf.line(X(sx), Y(sy), X(sx + 0.6), Y(sy))
        if kind == "many":
            many_marker(sx, sy, 1)
        elif kind == "one":
            one_marker(sx + 0.6, sy, -1, False)
        else:
            one_marker(sx + 0.6, sy, -1, True)
        text(sx + 0.85, sy, caption, "text", 8.6, INK)
        sy += 0.235
    text(sx, sy, "Цвет линии — по родительской таблице", "text", 8.6, MUTED)

    pdf.showPage()
    pdf.save()


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

    not_in_pdf = [n for n in tables if not any(n in col for col in PDF_COLUMNS)]
    if not_in_pdf:
        print("Новые таблицы без места в PDF_COLUMNS: " + ", ".join(sorted(not_in_pdf)))
        return 1

    page_xml = build_page(tables, relations)

    # Проверяем XML до записи файла: битая разметка в Visio не откроется
    ET.fromstring(page_xml)

    build_package(page_xml)
    build_pdf(tables, relations)

    with open(MERMAID, "w", encoding="utf-8") as mermaid_file:
        mermaid_file.write(build_mermaid(tables, relations))

    with zipfile.ZipFile(OUTPUT) as result:
        shapes = ET.fromstring(result.read("visio/pages/page1.xml")).findall(
            ".//{http://schemas.microsoft.com/office/visio/2012/main}Shape"
        )

    print(
        f"{OUTPUT}: таблиц {len(tables)}, связей {len(relations)}, фигур {len(shapes)}"
    )
    print(f"{PDF}: та же схема в PDF (предсказуемый рендер, без Visio)")
    print(f"{MERMAID}: та же схема текстом (mermaid) для просмотра в браузере")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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
# координаты задаём сами, рендер предсказуем. Шрифты DejaVu — с кириллицей,
# моноширинный нужен для ровных колонок в таблицах.
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
FONTS = {
    "text": f"{FONT_DIR}/DejaVuSans.ttf",
    "bold": f"{FONT_DIR}/DejaVuSans-Bold.ttf",
    "mono": f"{FONT_DIR}/DejaVuSansMono.ttf",
}


def register_fonts() -> None:
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    for name, path in FONTS.items():
        pdfmetrics.registerFont(TTFont(name, path))


def pdf_boxes(tables: dict[str, Table]) -> dict[str, tuple[float, float, float, float]]:
    """Прямоугольники таблиц: (лево, верх, ширина, высота) в дюймах сверху."""
    return {name: (LAYOUT[name][0], LAYOUT[name][1], BOX_W, table.height)
            for name, table in tables.items()}


def spread(index: int, count: int, low: float = 0.26, high: float = 0.74) -> float:
    """Доля высоты/ширины стороны таблицы для точки выхода или входа.

    Нужна, чтобы две связи, идущие с одной стороны, не выходили из одной точки.
    """
    if count <= 1:
        return (low + high) / 2
    return low + (high - low) * index / (count - 1)


def point_on_side(box: tuple[float, float, float, float], side: str, frac: float):
    """Точка на границе прямоугольника: (лево, верх, ширина, высота) + сторона."""
    left, top, width, height = box
    if side == "right":
        return left + width, top + height * frac
    if side == "left":
        return left, top + height * frac
    if side == "bottom":
        return left + width * frac, top + height
    return left + width * frac, top


def build_links(
    tables: dict[str, Table], relations: list[tuple[str, str, str, str]]
) -> list[list[tuple[float, float, float, float]]]:
    """Маршруты связей: для каждой связи — список ортогональных сегментов.

    Правила:
    * точки выхода и входа разнесены по стороне таблицы — линии не выходят
      из одной точки;
    * прямой маршрут выбирается только если он не проходит сквозь другие
      таблицы; иначе связь идёт по «шине» в жёлобе между колонками, и каждой
      шине достаётся своё смещение — линии не накладываются;
    * самоссылка рисуется петлёй у правого края.
    """
    boxes = pdf_boxes(tables)

    plans: list[dict] = []
    for child, _child_col, parent, _parent_col in relations:
        if child == parent:
            plans.append({"child": child, "parent": parent, "kind": "self"})
            continue

        cx, ctop, cw, _ch = boxes[child]
        px, ptop, pw, _ph = boxes[parent]

        if px >= cx + cw:
            out_side, in_side = "right", "left"
        elif px + pw <= cx:
            out_side, in_side = "left", "right"
        elif ptop >= ctop:
            out_side, in_side = "bottom", "top"
        else:
            out_side, in_side = "top", "bottom"

        plans.append({
            "child": child,
            "parent": parent,
            "kind": "h" if out_side in ("left", "right") else "v",
            "out_side": out_side,
            "in_side": in_side,
        })

    # Точки выхода и входа разносим по стороне: сортируем по тому, где
    # находится партнёр, чтобы линии не менялись местами без нужды
    out_usage: dict[tuple[str, str], list[int]] = {}
    in_usage: dict[tuple[str, str], list[int]] = {}
    for index, plan in enumerate(plans):
        if plan["kind"] == "self":
            continue
        out_usage.setdefault((plan["child"], plan["out_side"]), []).append(index)
        in_usage.setdefault((plan["parent"], plan["in_side"]), []).append(index)

    def partner_center(plan: dict) -> tuple[float, float]:
        _px, ptop, _pw, ph = boxes[plan["parent"]]
        _cx, ctop, _cw, ch = boxes[plan["child"]]
        return ptop + ph / 2, ctop + ch / 2

    for (_table, side), indexes in out_usage.items():
        horizontal = side in ("left", "right")
        indexes.sort(key=lambda i: partner_center(plans[i])[0 if horizontal else 1])
        for position, index in enumerate(indexes):
            plans[index]["out_frac"] = spread(position, len(indexes))

    for (_table, side), indexes in in_usage.items():
        horizontal = side in ("left", "right")
        indexes.sort(key=lambda i: partner_center(plans[i])[1 if horizontal else 0])
        for position, index in enumerate(indexes):
            plans[index]["in_frac"] = spread(position, len(indexes))

    for plan in plans:
        if plan["kind"] == "self":
            continue
        plan["x_out"], plan["y_out"] = point_on_side(
            boxes[plan["child"]], plan["out_side"], plan["out_frac"]
        )
        plan["x_in"], plan["y_in"] = point_on_side(
            boxes[plan["parent"]], plan["in_side"], plan["in_frac"]
        )


    def crosses_table(seg: tuple[float, float, float, float], skip: set[str]) -> bool:
        """Пересекает ли отрезок какую-то таблицу (кроме своих)."""
        x1, y1, x2, y2 = seg
        lo_x, hi_x = sorted((x1, x2))
        lo_y, hi_y = sorted((y1, y2))
        for name, (bx, btop, bw, bh) in boxes.items():
            if name in skip:
                continue
            if (bx < hi_x - 0.02 and bx + bw > lo_x + 0.02
                    and btop < hi_y - 0.02 and btop + bh > lo_y + 0.02):
                return True
        return False

    # Прямой маршрут (три сегмента) пробуем для каждой связи; если он задевает
    # чужую таблицу — связь переводим на шину
    for plan in plans:
        if plan["kind"] == "self":
            continue

        x_out, y_out, x_in, y_in = plan["x_out"], plan["y_out"], plan["x_in"], plan["y_in"]
        skip = {plan["child"], plan["parent"]}

        if plan["kind"] == "h":
            mid = (x_out + x_in) / 2
            trial = [(x_out, y_out, mid, y_out),
                     (mid, y_out, mid, y_in),
                     (mid, y_in, x_in, y_in)]
            plan["mid"] = mid
        else:
            mid_y = (y_out + y_in) / 2
            trial = [(x_out, y_out, x_out, mid_y),
                     (x_out, mid_y, x_in, mid_y),
                     (x_in, mid_y, x_in, y_in)]
            plan["mid"] = mid_y

        plan["need_bus"] = any(crosses_table(seg, skip) for seg in trial)

    # Прямые маршруты в одном и том же зазоре разносем по середине, иначе их
    # вертикальные (или горизонтальные) участки совпадут и линии сольются
    direct_groups: dict[tuple[float, float, str], list[int]] = {}
    for index, plan in enumerate(plans):
        if plan["kind"] == "self" or plan["need_bus"]:
            continue
        key = (round(plan["x_out"], 2), round(plan["x_in"], 2), plan["kind"])
        direct_groups.setdefault(key, []).append(index)

    for (_x_out, _x_in, _kind), indexes in direct_groups.items():
        if len(indexes) < 2:
            continue
        indexes.sort(key=lambda i: plans[i]["y_out"])
        for position, index in enumerate(indexes):
            plans[index]["mid"] += (position - (len(indexes) - 1) / 2) * 0.09

    # Шины: жёлоб между колонками. Смещение каждой следующей шины в том же
    # жёлобе увеличиваем, но не выходим за половину зазора
    columns = sorted({round(box[0], 2) for box in boxes.values()})

    def gap_of(left: float, sign: float) -> float:
        if sign > 0:
            right = [c for c in columns if c > left]
            return (right[0] - (left + BOX_W)) if right else (PAGE_W - (left + BOX_W))
        lefts = [c for c in columns if c < left]
        return (left - (lefts[-1] + BOX_W)) if lefts else left

    bus_groups: dict[tuple[float, float], list[int]] = {}
    for index, plan in enumerate(plans):
        if plan["kind"] == "self" or not plan.get("need_bus"):
            continue
        left = boxes[plan["child"]][0]
        sign = 1.0 if left + BOX_W / 2 > PAGE_W / 2 else -1.0
        edge = left + BOX_W if sign > 0 else left
        bus_groups.setdefault((round(edge, 2), sign), []).append(index)

    for ((edge, sign), indexes) in bus_groups.items():
        indexes.sort(key=lambda i: plans[i]["y_out"])
        gap = gap_of(edge - BOX_W if sign > 0 else edge, sign)
        count = len(indexes)
        for position, index in enumerate(indexes):
            # Равномерно по жёлобу: при двух связях — 1/3 и 2/3 зазора
            offset = gap * (position + 1) / (count + 1)
            plans[index]["bus"] = edge + sign * offset
            plans[index]["bus_sign"] = sign
            plans[index]["bus_limit"] = edge + sign * (gap - 0.06)

    def make_links() -> list[list[tuple[float, float, float, float]]]:
        result: list[list[tuple[float, float, float, float]]] = []
        for plan in plans:
            if plan["kind"] == "self":
                left, top, width, height = boxes[plan["child"]]
                edge = left + width
                y_out = top + height * 0.28
                y_in = top + height * 0.72
                result.append([(edge, y_out, edge + 0.42, y_out),
                               (edge + 0.42, y_out, edge + 0.42, y_in),
                               (edge + 0.42, y_in, edge, y_in)])
                continue

            x_out, y_out = plan["x_out"], plan["y_out"]
            x_in, y_in = plan["x_in"], plan["y_in"]

            if plan["need_bus"]:
                bus = plan["bus"]
                result.append([(x_out, y_out, bus, y_out),
                               (bus, y_out, bus, y_in),
                               (bus, y_in, x_in, y_in)])
            elif plan["kind"] == "h":
                mid = plan["mid"]
                result.append([(x_out, y_out, mid, y_out),
                               (mid, y_out, mid, y_in),
                               (mid, y_in, x_in, y_in)])
            else:
                mid_y = plan["mid"]
                result.append([(x_out, y_out, x_out, mid_y),
                               (x_out, mid_y, x_in, mid_y),
                               (x_in, mid_y, x_in, y_in)])
        return result

    def is_horizontal(seg: tuple[float, float, float, float]) -> bool:
        return abs(seg[1] - seg[3]) < 1e-9

    def overlapping(links: list[list[tuple[float, float, float, float]]]) -> set[int]:
        """Связи, чьи линии накладываются друг на друга (идят по одной прямой)."""
        flat = [(index, seg) for index, link in enumerate(links) for seg in link]
        found: set[int] = set()
        for first in range(len(flat)):
            for second in range(first + 1, len(flat)):
                i, a = flat[first]
                j, b = flat[second]
                if i == j:
                    continue
                if is_horizontal(a) and is_horizontal(b) and abs(a[1] - b[1]) < 0.01:
                    a1, a2 = sorted((a[0], a[2]))
                    b1, b2 = sorted((b[0], b[2]))
                    if min(a2, b2) - max(a1, b1) > 0.02:
                        found.update((i, j))
                elif (not is_horizontal(a) and not is_horizontal(b)
                        and abs(a[0] - b[0]) < 0.01):
                    a1, a2 = sorted((a[1], a[3]))
                    b1, b2 = sorted((b[1], b[3]))
                    if min(a2, b2) - max(a1, b1) > 0.02:
                        found.update((i, j))
        return found

    links = make_links()

    # Пары линий, случайно попавшие на одну прямую (например, прямая связь и
    # шина в том же жёлобе), разводим сдвигом шины
    for _attempt in range(12):
        clashes = overlapping(links)
        if not clashes:
            break
        moved = False
        for index in clashes:
            plan = plans[index]
            if "bus" not in plan:
                continue
            sign = plan["bus_sign"]
            candidate = plan["bus"] + sign * 0.05
            if sign * (candidate - plan["bus_limit"]) > 0:
                candidate = plan["bus"] - sign * 0.05
            plan["bus"] = candidate
            moved = True
        if not moved:
            break
        links = make_links()
    return links

def build_pdf(tables: dict[str, Table], relations: list[tuple[str, str, str, str]]) -> None:
    """Рисует схему в PDF: связи с «мостиками» на пересечениях, таблицы поверх."""
    import math

    from reportlab.lib.colors import HexColor
    from reportlab.pdfgen import canvas

    register_fonts()

    width_pt, height_pt = PAGE_W * 72, PAGE_H * 72
    pdf = canvas.Canvas(PDF, pagesize=(width_pt, height_pt))
    pdf.setTitle("PPE Tracker — схема базы данных")

    def y(top: float) -> float:
        return height_pt - top * 72

    boxes = pdf_boxes(tables)
    links = build_links(tables, relations)

    # --- геометрия связей: пересечения и «мостики» ------------------------
    bridge = 0.08  # радиус полуокружности, дюймы
    kappa = 0.5523  # коэффициент аппроксимации четверти круга кривой Безье

    def horizontal(seg: tuple[float, float, float, float]) -> bool:
        return abs(seg[1] - seg[3]) < 1e-9

    def crossing(a, b):
        """Точка пересечения двух ортогональных сегментов (или None)."""
        if horizontal(a) == horizontal(b):
            return None
        h, v = (a, b) if horizontal(a) else (b, a)
        hx1, hx2 = sorted((h[0], h[2]))
        vy1, vy2 = sorted((v[1], v[3]))
        if hx1 < v[0] < hx2 and vy1 < h[1] < vy2:
            return v[0], h[1]
        return None

    def free_side(x: float, y: float) -> float:
        """Куда рисовать мост: 1 — вправо, -1 — влево (где свободнее)."""
        def blocked(direction: float) -> bool:
            probe = x + direction * (bridge + 0.03)
            for _name, (bx, btop, bw, bh) in boxes.items():
                if bx <= probe <= bx + bw and btop <= y <= btop + bh:
                    return True
            return any(abs(vx - probe) < 0.07 for vx in vertical_xs)

        right_ok = not blocked(1.0)
        left_ok = not blocked(-1.0)
        if right_ok == left_ok:
            return 1.0
        return 1.0 if right_ok else -1.0

    def merge_marks(values: list[float]) -> list[float]:
        """Схлопывает близкие пересечения: два моста подряд не рисуются."""
        merged: list[float] = []
        for value in sorted(values):
            if merged and value - merged[-1] < bridge * 2.2:
                continue
            merged.append(value)
        return merged

    vertical_xs = sorted({round(seg[0], 3) for link in links for seg in link
                          if not horizontal(seg)})

    def stroke_link(segments: list[tuple[float, float, float, float]],
                    crossings: list[list[float]]) -> None:
        pdf.setStrokeColor(HexColor(ACCENT))
        pdf.setLineWidth(1.2)

        for seg, points in zip(segments, crossings, strict=False):
            x1, y1, x2, y2 = seg
            path = pdf.beginPath()

            if horizontal(seg):
                forward = x2 >= x1
                start, end = (x1, x2) if forward else (x2, x1)
                marks = merge_marks([p[0] for p in points])
                path.moveTo(start * 72, y(y1))
                position = start
                for mark in marks:
                    if mark - bridge <= position or mark + bridge >= end:
                        continue
                    path.lineTo((mark - bridge) * 72, y(y1))
                    path.curveTo((mark - bridge) * 72, y(y1) + kappa * bridge * 72,
                                 (mark - kappa * bridge) * 72, y(y1) + bridge * 72,
                                 mark * 72, y(y1) + bridge * 72)
                    path.curveTo((mark + kappa * bridge) * 72, y(y1) + bridge * 72,
                                 (mark + bridge) * 72, y(y1) + kappa * bridge * 72,
                                 (mark + bridge) * 72, y(y1))
                    position = mark + bridge
                path.lineTo(end * 72, y(y1))
            else:
                forward = y2 >= y1
                start, end = (y1, y2) if forward else (y2, y1)
                marks = merge_marks([p[1] for p in points])
                path.moveTo(x1 * 72, y(start))
                position = start
                for mark in marks:
                    if mark - bridge <= position or mark + bridge >= end:
                        continue
                    # Мост вбок; сторону выбираем по свободному месту рядом:
                    # справа может быть соседняя линия или таблица
                    side = free_side(x1, mark)
                    path.lineTo(x1 * 72, y(mark - bridge))
                    path.curveTo(x1 * 72 + side * kappa * bridge * 72, y(mark - bridge),
                                 x1 * 72 + side * bridge * 72, y(mark - kappa * bridge),
                                 x1 * 72 + side * bridge * 72, y(mark))
                    path.curveTo(x1 * 72 + side * bridge * 72, y(mark + kappa * bridge),
                                 x1 * 72 + side * kappa * bridge * 72, y(mark + bridge),
                                 x1 * 72, y(mark + bridge))
                    position = mark + bridge
                path.lineTo(x1 * 72, y(end))

            pdf.drawPath(path, stroke=1, fill=0)

        # Стрелка на последнем сегменте — у родительской таблицы
        x1, y1, x2, y2 = segments[-1]
        angle = math.atan2(-(y2 - y1), x2 - x1)
        for delta in (-0.42, 0.42):
            pdf.line(x2 * 72, y(y2),
                     x2 * 72 - 5.5 * math.cos(angle + delta),
                     y(y2) + 5.5 * math.sin(angle + delta))

    # 1. Связи первыми: таблицы рисуются поверх
    drawn: list[tuple[float, float, float, float]] = []
    overlaps = 0
    crossings_total = 0
    for link in links:
        marks: list[list[float]] = []
        for seg in link:
            segment_marks = [list(point) for prev in drawn
                             if (point := crossing(seg, prev)) is not None]
            crossings_total += len(segment_marks)
            marks.append(segment_marks)

            for prev in drawn:
                if horizontal(seg) and horizontal(prev) and abs(seg[1] - prev[1]) < 0.01:
                    a1, a2 = sorted((seg[0], seg[2]))
                    b1, b2 = sorted((prev[0], prev[2]))
                    if min(a2, b2) - max(a1, b1) > 0.02:
                        overlaps += 1
                if (not horizontal(seg) and not horizontal(prev)
                        and abs(seg[0] - prev[0]) < 0.01):
                    a1, a2 = sorted((seg[1], seg[3]))
                    b1, b2 = sorted((prev[1], prev[3]))
                    if min(a2, b2) - max(a1, b1) > 0.02:
                        overlaps += 1

            drawn.append(seg)
        stroke_link(link, marks)

    print(f"  связей: {len(links)} · пересечений: {crossings_total} "
          f"(показаны мостиками) · наложений: {overlaps}")
    if overlaps:
        print("  ВНИМАНИЕ: линии накладываются друг на друга — это недопустимо")

    # 2. Таблицы
    for name, table in tables.items():
        left, top, w, h = boxes[name]

        pdf.setFillColor(HexColor(BRAND))
        pdf.setStrokeColor(HexColor(BRAND))
        pdf.setLineWidth(0.7)
        pdf.roundRect(left * 72, y(top + HEADER_H), w * 72, HEADER_H * 72,
                      3, stroke=1, fill=1)
        pdf.setFillColor(HexColor("#FFFFFF"))
        pdf.setFont("bold", 7.6)
        pdf.drawCentredString((left + w / 2) * 72, y(top + HEADER_H / 2 + 0.04),
                              TABLE_TITLES.get(name, name))

        body_top = top + HEADER_H
        pdf.setFillColor(HexColor("#FFFFFF"))
        pdf.setStrokeColor(HexColor(LINE))
        pdf.roundRect(left * 72, y(top + h), w * 72, (h - HEADER_H) * 72,
                      3, stroke=1, fill=1)

        pdf.setFillColor(HexColor(INK))
        pdf.setFont("mono", 6.4)
        text_object = pdf.beginText((left + 0.07) * 72, y(body_top + 0.13))
        text_object.setLeading(8.4)
        for column in table.columns:
            text_object.textLine(column_line(column).rstrip())
        pdf.drawText(text_object)

    # 3. Заголовок и легенда — поверх всего
    pdf.setFillColor(HexColor(BRAND))
    pdf.setStrokeColor(HexColor(BRAND))
    pdf.roundRect(0.5 * 72, y(0.72), 9.0 * 72, 0.42 * 72, 3, stroke=1, fill=1)
    pdf.setFillColor(HexColor("#FFFFFF"))
    pdf.setFont("bold", 14)
    pdf.drawString(0.62 * 72, y(0.58), "PPE Tracker — схема базы данных")

    pdf.setFillColor(HexColor(INK))
    pdf.setFont("text", 8)
    pdf.drawString(0.5 * 72, y(0.95),
                   f"PostgreSQL 16 · таблиц: {len(tables)} · связей: {len(relations)} · "
                   f"сгенерировано из information_schema {date.today().strftime('%d.%m.%Y')}")

    pdf.setFillColor(HexColor("#FFFFFF"))
    pdf.setStrokeColor(HexColor(LINE))
    pdf.roundRect(11.5 * 72, y(1.04), 8.6 * 72, 0.74 * 72, 3, stroke=1, fill=1)
    pdf.setFillColor(HexColor(INK))
    pdf.setFont("text", 7.4)
    text_object = pdf.beginText(11.65 * 72, y(0.52))
    text_object.setLeading(9.4)
    for line in [
        "PK — первичный ключ, U — уникальное поле, NN — NOT NULL",
        "→ в поле — внешний ключ и правило ON DELETE",
        "Стрелка ведёт от дочерней таблицы к родительской",
        "Пересечение связей показано «мостиком» — полуокружностью",
    ]:
        text_object.textLine(line)
    pdf.drawText(text_object)

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

# app/main.py
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from app.api.v1.endpoints import employees, ppe_categories, ppe_items, ws, departments, positions, position_ppe_norms

BASE_DIR = Path(__file__).resolve().parent

app = FastAPI(title="PPE Tracker API")

# --- Шаблоны ---
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))


def format_date(value):
    return value.strftime("%d.%m.%Y") if value else ""


templates.env.filters["ru_date"] = format_date

# --- Статика ---
app.mount(
    "/static",
    StaticFiles(directory=str(BASE_DIR / "static")),
    name="static",
)

# --- HTTP-роутеры ---
app.include_router(employees.router, prefix="/api/v1")
app.include_router(departments.router, prefix="/api/v1")
app.include_router(positions.router, prefix="/api/v1")
app.include_router(position_ppe_norms.router, prefix="/api/v1")
app.include_router(ppe_categories.router, prefix="/api/v1")
app.include_router(ppe_items.router, prefix="/api/v1")

# --- WebSocket-роутер ---
app.include_router(ws.router)


# --- HTML-страницы ---
@app.get("/employees", response_class=HTMLResponse)
async def employees_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="employees/list.html",
        context={"title": "Сотрудники"},
    )


@app.get("/employees/{employee_id}/edit", response_class=HTMLResponse)
async def employee_edit_page(request: Request, employee_id: int):
    return templates.TemplateResponse(
        request=request,
        name="employees/edit.html",
        context={"title": "Редактирование", "employee_id": employee_id},
    )


@app.get("/ppe-categories", response_class=HTMLResponse)
async def ppe_categories_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="ppe_categories/list.html",
        context={"title": "Категории СИЗ"},
    )


@app.get("/ppe-categories/{category_id}/edit", response_class=HTMLResponse)
async def ppe_category_edit_page(request: Request, category_id: int):
    return templates.TemplateResponse(
        request=request,
        name="ppe_categories/edit.html",
        context={"title": "Редактирование категории", "category_id": category_id},
    )


@app.get("/")
async def root():
    return {"message": "Привет! Сервер учета СИЗ работает."}


@app.get("/ppe-items", response_class=HTMLResponse)
async def ppe_items_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/list.html",
        context={"title": "Наименования СИЗ"},
    )


@app.get("/ppe-items/{item_id}/edit", response_class=HTMLResponse)
async def ppe_item_edit_page(request: Request, item_id: int):
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/edit.html",
        context={"title": "Редактирование наименования", "item_id": item_id},
    )


@app.get("/departments", response_class=HTMLResponse)
async def departments_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="departments/list.html",
        context={"title": "Подразделения"},
    )

@app.get("/departments/{dept_id}/edit", response_class=HTMLResponse)
async def department_edit_page(request: Request, dept_id: int):
    return templates.TemplateResponse(
        request=request,
        name="departments/edit.html",
        context={"title": "Редактирование подразделения", "dept_id": dept_id},
    )

@app.get("/positions", response_class=HTMLResponse)
async def positions_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="positions/list.html",
        context={"title": "Должности"},
    )

@app.get("/positions/{pos_id}/edit", response_class=HTMLResponse)
async def position_edit_page(request: Request, pos_id: int):
    return templates.TemplateResponse(
        request=request,
        name="positions/edit.html",
        context={"title": "Редактирование должности", "pos_id": pos_id},
    )

@app.get("/norms", response_class=HTMLResponse)
async def norms_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="norms/list.html",
        context={"title": "Нормы выдачи СИЗ"},
    )

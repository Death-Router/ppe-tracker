from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from app.api.v1.endpoints import (
    employees, ppe_items, ws, departments, positions,
    position_ppe_norms, employee_ppe_issues, ppe_sizes, export, import_data, auth, units,
    ppe_functions, ppe_size_groups
)

BASE_DIR = Path(__file__).resolve().parent

app = FastAPI(title="PPE Tracker API")
app.add_middleware(SessionMiddleware, secret_key="super-secret-key-change-in-production")

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
app.include_router(ppe_items.router, prefix="/api/v1")
app.include_router(departments.router, prefix="/api/v1")
app.include_router(positions.router, prefix="/api/v1")
app.include_router(position_ppe_norms.router, prefix="/api/v1")
app.include_router(employee_ppe_issues.router, prefix="/api/v1")
app.include_router(ppe_sizes.router, prefix="/api/v1")
app.include_router(export.router, prefix="/api/v1")
app.include_router(import_data.router, prefix="/api/v1")
app.include_router(auth.router, prefix="/api/v1")
app.include_router(units.router, prefix="/api/v1")
app.include_router(ppe_functions.router, prefix="/api/v1")
app.include_router(ppe_size_groups.router, prefix="/api/v1")

# --- WebSocket-роутер ---
app.include_router(ws.router)


def check_auth(request: Request):
    """Проверяет наличие сессии. Если нет — возвращает RedirectResponse."""
    if not request.session.get("user_id"):
        return RedirectResponse(url="/login", status_code=303)
    return None


# --- HTML-страницы ---
@app.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="login.html",
        context={"title": "Вход"},
    )

@app.get("/employees", response_class=HTMLResponse)
async def employees_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="employees/list.html",
        context={"title": "Сотрудники"},
    )

@app.get("/employees/{employee_id}/edit", response_class=HTMLResponse)
async def employee_edit_page(request: Request, employee_id: int):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="employees/edit.html",
        context={"title": "Редактирование", "employee_id": employee_id},
    )

@app.get("/ppe", response_class=HTMLResponse)
async def ppe_tabs_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe/tabs.html",
        context={"title": "Управление СИЗ"},
    )

@app.get("/structure", response_class=HTMLResponse)
async def structure_tabs_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="structure/tabs.html",
        context={"title": "Структура"},
    )



@app.get("/ppe-items", response_class=HTMLResponse)
async def ppe_items_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/list.html",
        context={"title": "Наименования СИЗ"},
    )

@app.get("/ppe-items/{item_id}/edit", response_class=HTMLResponse)
async def ppe_item_edit_page(request: Request, item_id: int):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/edit.html",
        context={"title": "Редактирование наименования", "item_id": item_id},
    )

@app.get("/departments", response_class=HTMLResponse)
async def departments_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="departments/list.html",
        context={"title": "Подразделения"},
    )

@app.get("/departments/{dept_id}/edit", response_class=HTMLResponse)
async def department_edit_page(request: Request, dept_id: int):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="departments/edit.html",
        context={"title": "Редактирование подразделения", "dept_id": dept_id},
    )

@app.get("/positions", response_class=HTMLResponse)
async def positions_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="positions/list.html",
        context={"title": "Должности"},
    )

@app.get("/positions/{pos_id}/edit", response_class=HTMLResponse)
async def position_edit_page(request: Request, pos_id: int):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="positions/edit.html",
        context={"title": "Редактирование должности", "pos_id": pos_id},
    )

@app.get("/norms", response_class=HTMLResponse)
async def norms_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="norms/list.html",
        context={"title": "Нормы выдачи СИЗ"},
    )

@app.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="settings.html",
        context={"title": "Настройки"},
    )

@app.get("/units", response_class=HTMLResponse)
async def units_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="units/list.html",
        context={"title": "Единицы измерения"},
    )

@app.get("/")
async def root():
    return RedirectResponse(url="/employees")

@app.get("/ppe-functions", response_class=HTMLResponse)
async def ppe_functions_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_functions/list.html",
        context={"title": "Функции СИЗ"},
    )

@app.get("/ppe-size-groups", response_class=HTMLResponse)
async def ppe_size_groups_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_size_groups/list.html",
        context={"title": "Размерные группы"},
    )

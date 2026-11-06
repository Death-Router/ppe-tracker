import asyncio
import logging
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.middleware.sessions import SessionMiddleware

from app.api.v1.endpoints import (
    auth,
    departments,
    employee_ppe_issues,
    employees,
    export,
    import_data,
    position_ppe_norms,
    positions,
    ppe_functions,
    ppe_items,
    ppe_size_groups,
    ppe_sizes,
    typical_norms,
    units,
    users,
    ws,
)
from app.core.config import settings
from app.core.constants import HEIGHT_GRID
from app.core.csrf import csrf_token_for, require_csrf
from app.core.deps import get_current_active_user
from app.db.session import get_db

BASE_DIR = Path(__file__).resolve().parent

logger = logging.getLogger(__name__)

# ENVIRONMENT влияет на то, что видно снаружи: в продакшене схема API закрыта,
# а 500 не раскрывает внутренности. Сам по себе флаг ничего не включает —
# reload и монтирование кода задаются при запуске (docker-compose.prod.yml).
IS_PRODUCTION = settings.ENVIRONMENT.strip().lower() == "production"

app = FastAPI(
    title="PPE Tracker API",
    docs_url=None if IS_PRODUCTION else "/docs",
    redoc_url=None if IS_PRODUCTION else "/redoc",
    openapi_url=None if IS_PRODUCTION else "/openapi.json",
)


@app.get("/healthz", include_in_schema=False)
async def healthz(db: AsyncSession = Depends(get_db)) -> dict[str, str]:
    """Готовность для docker healthcheck: приложение живо и БД отвечает."""
    try:
        await asyncio.wait_for(db.execute(text("SELECT 1")), timeout=3)
    except Exception as exc:
        logger.warning("healthz: база недоступна", exc_info=True)
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ok"}


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    """Отдаём причину ошибки, а не пустой 500.

    По умолчанию FastAPI на необработанном исключении возвращает пустое тело,
    и клиент показывает голое «HTTP 500» — по такому сообщению причину не
    найти ни в интерфейсе, ни в логе, если трассировка не попала в вывод.

    В продакшене текст исключения наружу не отдаём: в нём бывают пути, SQL и
    имена таблиц. Подробности остаются в логе.
    """
    logger.exception("Необработанная ошибка на %s %s", request.method, request.url.path)
    detail = (
        "Внутренняя ошибка сервера"
        if IS_PRODUCTION
        else f"Внутренняя ошибка сервера: {type(exc).__name__}: {exc}"
    )
    return JSONResponse(status_code=500, content={"detail": detail})


app.add_middleware(
    SessionMiddleware,
    secret_key=settings.SECRET_KEY,
    session_cookie="ppe_session",
    max_age=settings.SESSION_MAX_AGE,
    same_site="lax",
    https_only=settings.SESSION_COOKIE_SECURE,
)

# --- Шаблоны ---
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))

def format_date(value):
    return value.strftime("%d.%m.%Y") if value else ""

templates.env.filters["ru_date"] = format_date

# Токен CSRF доступен шаблонам как {{ csrf_token(request) }}
templates.env.globals["csrf_token"] = csrf_token_for

# --- Статика ---
app.mount(
    "/static",
    StaticFiles(directory=str(BASE_DIR / "static")),
    name="static",
)

# --- HTTP-роутеры ---
# Авторизация включается централизованно, на уровне роутера: так новый эндпоинт
# нельзя случайно оставить открытым, забыв добавить Depends в обработчик.
PROTECTED_ROUTERS = (
    employees.router,
    ppe_items.router,
    departments.router,
    positions.router,
    position_ppe_norms.router,
    employee_ppe_issues.router,
    ppe_sizes.router,
    export.router,
    import_data.router,
    units.router,
    ppe_functions.router,
    ppe_size_groups.router,
    typical_norms.router,
    users.router,
)

for _router in PROTECTED_ROUTERS:
    app.include_router(
        _router,
        prefix="/api/v1",
        dependencies=[
            # CSRF проверяется до похода в базу: чужой запрос отсекаем
            # без лишнего соединения
            Depends(require_csrf),
            Depends(get_current_active_user),
        ],
    )

# Вход и выход доступны без сессии. CSRF для logout проверяется внутри
# обработчика, а для login не нужен: до первого входа токена ещё нет.
app.include_router(auth.router, prefix="/api/v1")

# --- WebSocket-роутер ---
app.include_router(ws.router)


def check_auth(request: Request):
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
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="employees/list.html",
        # Сетка роста задаётся Положением: список значений приходит из
        # app/core/constants.py, чтобы шаблон и серверная проверка не разошлись
        context={"title": "Сотрудники", "height_grid": HEIGHT_GRID},
    )

@app.get("/employees/{employee_id}/edit")
async def employee_edit_page(request: Request, employee_id: int):
    """Старый адрес карточки: сотрудник теперь правится в модалке на списке."""
    redirect = check_auth(request)
    if redirect:
        return redirect
    return RedirectResponse(url="/employees", status_code=303)

@app.get("/ppe")
async def ppe_tabs_page(request: Request):
    """Старый адрес раздела: ведёт на первую вкладку.

    Раньше здесь была страница с iframe, из-за которой модалки открывались
    внутри рамки. Теперь каждая вкладка — обычная страница.
    """
    redirect = check_auth(request)
    if redirect:
        return redirect
    return RedirectResponse(url="/ppe-items", status_code=303)

@app.get("/structure")
async def structure_tabs_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return RedirectResponse(url="/departments", status_code=303)

@app.get("/ppe-items", response_class=HTMLResponse)
async def ppe_items_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/list.html",
        context={"title": "Наименования СИЗ"},
    )

@app.get("/ppe-items/{item_id}/edit", response_class=HTMLResponse)
async def ppe_item_edit_page(request: Request, item_id: int):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_items/edit.html",
        context={"title": "Редактирование наименования", "item_id": item_id},
    )

@app.get("/departments", response_class=HTMLResponse)
async def departments_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="departments/list.html",
        context={"title": "Подразделения"},
    )

@app.get("/departments/{dept_id}/edit", response_class=HTMLResponse)
async def department_edit_page(request: Request, dept_id: int):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="departments/edit.html",
        context={"title": "Редактирование подразделения", "dept_id": dept_id},
    )

@app.get("/positions", response_class=HTMLResponse)
async def positions_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="positions/list.html",
        context={"title": "Должности"},
    )

@app.get("/positions/{pos_id}/edit", response_class=HTMLResponse)
async def position_edit_page(request: Request, pos_id: int):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="positions/edit.html",
        context={"title": "Редактирование должности", "pos_id": pos_id},
    )

@app.get("/norms", response_class=HTMLResponse)
async def norms_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="norms/list.html",
        context={"title": "Нормы выдачи СИЗ"},
    )

@app.get("/typical-norms", response_class=HTMLResponse)
async def typical_norms_page(request: Request):
    """Справочник пунктов норм — вкладка раздела «Нормы выдачи»."""
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="typical_norms/list.html",
        context={"title": "Типовые нормы"},
    )

@app.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="settings.html",
        context={"title": "Настройки"},
    )

@app.get("/units", response_class=HTMLResponse)
async def units_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="units/list.html",
        context={"title": "Единицы измерения"},
    )

@app.get("/users", response_class=HTMLResponse)
async def users_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="users/list.html",
        context={"title": "Пользователи"},
    )

@app.get("/")
async def root():
    return RedirectResponse(url="/employees")

@app.get("/ppe-functions", response_class=HTMLResponse)
async def ppe_functions_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_functions/list.html",
        context={"title": "Функции СИЗ"},
    )

@app.get("/ppe-size-groups", response_class=HTMLResponse)
async def ppe_size_groups_page(request: Request):
    redirect = check_auth(request)
    if redirect:
        return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_size_groups/list.html",
        context={"title": "Размерные группы"},
    )

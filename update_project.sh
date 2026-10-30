#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно обновляем main.py (добавляем /ppe и /structure)..."

# Полностью перезаписываем main.py
cat > app/main.py << 'EOF'
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.sessions import SessionMiddleware

from app.api.v1.endpoints import (
    employees, ppe_categories, ppe_items, ws, departments, positions,
    position_ppe_norms, employee_ppe_issues, ppe_sizes, export, import_data, auth, units
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
app.include_router(ppe_categories.router, prefix="/api/v1")
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

@app.get("/ppe-categories", response_class=HTMLResponse)
async def ppe_categories_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_categories/list.html",
        context={"title": "Категории СИЗ"},
    )

@app.get("/ppe-categories/{category_id}/edit", response_class=HTMLResponse)
async def ppe_category_edit_page(request: Request, category_id: int):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_categories/edit.html",
        context={"title": "Редактирование категории", "category_id": category_id},
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
EOF

echo "🔧 Обновляем base.html (убираем выпадающие меню)..."

cat > app/templates/base.html << 'EOF'
{# app/templates/base.html #}
<!doctype html>
<html lang="ru">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{% block title %}{{ title or "Учёт СИЗ" }}{% endblock %}</title>

    <!-- Google Fonts (Inter) -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">

    <!-- Bootstrap 5 CSS -->
    <link
        href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css"
        rel="stylesheet"
        integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH"
        crossorigin="anonymous">
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <link rel="stylesheet" href="{{ url_for('static', path='css/app.css') }}">
    {% block head %}{% endblock %}
</head>
<body class="bg-light">

<nav class="navbar navbar-expand-lg navbar-dark bg-purple mb-4 shadow-sm navbar-bottom-line">
    <div class="container-fluid">
        <a class="navbar-brand text-brand-orange" href="/settings" title="Настройки" style="font-size: 3rem;">
            <i class="bi bi-gear-fill"></i>
        </a>
        
        <button class="navbar-toggler" type="button" data-bs-toggle="collapse"
                data-bs-target="#mainNav">
            <span class="navbar-toggler-icon"></span>
        </button>
        
        <div class="collapse navbar-collapse" id="mainNav">
            <ul class="navbar-nav mx-auto">
                <li class="nav-item text-center">
                    <a class="nav-link {% if '/employees' in request.url.path %}active{% endif %}" href="/employees">
                        <i class="bi bi-people d-block" style="font-size: 1.2rem;"></i>
                        <span style="font-size: 0.7rem;">Сотрудники</span>
                    </a>
                </li>
                <li class="nav-item text-center">
                    <a class="nav-link {% if '/ppe' in request.url.path or '/norms' in request.url.path or '/units' in request.url.path %}active{% endif %}" href="/ppe">
                        <i class="bi bi-box-seam d-block" style="font-size: 1.2rem;"></i>
                        <span style="font-size: 0.7rem;">СИЗ</span>
                    </a>
                </li>
                <li class="nav-item text-center">
                    <a class="nav-link {% if '/structure' in request.url.path or '/departments' in request.url.path or '/positions' in request.url.path %}active{% endif %}" href="/structure">
                        <i class="bi bi-diagram-3 d-block" style="font-size: 1.2rem;"></i>
                        <span style="font-size: 0.7rem;">Структура</span>
                    </a>
                </li>
            </ul>
            <ul class="navbar-nav">
                <li class="nav-item text-center">
                    <a class="nav-link" href="#" onclick="event.preventDefault(); fetch('/api/v1/auth/logout', {method: 'POST'}).then(() => window.location.href='/login');">
                        <i class="bi bi-box-arrow-right d-block" style="font-size: 1.2rem;"></i>
                        <span style="font-size: 0.7rem;">Выйти</span>
                    </a>
                </li>
            </ul>
        </div>
    </div>
</nav>

<main class="container pb-5">
    {% block content %}{% endblock %}
</main>

<!-- Контейнер для toast-уведомлений -->
<div class="toast-container position-fixed top-0 end-0 p-3" id="toast-container"
     style="z-index: 1100;"></div>

<!-- Bootstrap 5 Bundle (включает Popper) -->
<script
    src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"
    integrity="sha384-YvpcrYf0tY3lHB60NNkmXc5s9fDVZLESaAA55NDzOxhy9GkcIdslK1eN7N6jIeHz"
    crossorigin="anonymous"></script>

<!-- Хелпер для toast'ов (доступен всем скриптам) -->
<script>
    window.showToast = function (message, variant = 'info') {
        const container = document.getElementById('toast-container');
        const el = document.createElement('div');
        el.className = `toast align-items-center text-bg-${variant} border-0`;
        el.setAttribute('role', 'alert');
        el.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">${message}</div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto"
                        data-bs-dismiss="toast"></button>
            </div>`;
        container.appendChild(el);
        const t = new bootstrap.Toast(el, { delay: 4000 });
        t.show();
        el.addEventListener('hidden.bs.toast', () => el.remove());
    };
</script>

<!-- Общие хелперы (API, WebSocket, Forms) -->
<script src="{{ url_for('static', path='js/common/api.js') }}"></script>
<script src="{{ url_for('static', path='js/common/ws.js') }}"></script>
<script src="{{ url_for('static', path='js/common/form.js') }}"></script>

<!-- Блок для скриптов конкретной страницы -->
{% block scripts %}{% endblock %}

</body>
</html>
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Страницы с вкладками и навбар обновлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force update main.py and base.html for tabbed pages"
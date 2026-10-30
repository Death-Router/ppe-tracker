#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Создаем страницы-обертки с вкладками (через iframe)..."

# 1. Создаем шаблон для СИЗ
mkdir -p app/templates/ppe
cat > app/templates/ppe/tabs.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-12">
        <h1 class="h3 mb-3">Управление СИЗ</h1>
        
        <ul class="nav nav-tabs mb-3" id="ppeTabs" role="tablist">
            <li class="nav-item" role="presentation">
                <button class="nav-link active" id="items-tab" data-bs-toggle="tab" data-bs-target="#items" type="button" role="tab">Наименования СИЗ</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="norms-tab" data-bs-toggle="tab" data-bs-target="#norms" type="button" role="tab">Нормы выдачи</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="categories-tab" data-bs-toggle="tab" data-bs-target="#categories" type="button" role="tab">Категории СИЗ</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="units-tab" data-bs-toggle="tab" data-bs-target="#units" type="button" role="tab">Единицы измерения</button>
            </li>
        </ul>

        <div class="tab-content" id="ppeTabsContent">
            <div class="tab-pane fade show active" id="items" role="tabpanel">
                <iframe src="/ppe-items?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="norms" role="tabpanel">
                <iframe src="/norms?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="categories" role="tabpanel">
                <iframe src="/ppe-categories?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="units" role="tabpanel">
                <iframe src="/units?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# 2. Создаем шаблон для Структуры
mkdir -p app/templates/structure
cat > app/templates/structure/tabs.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-12">
        <h1 class="h3 mb-3">Структура предприятия</h1>
        
        <ul class="nav nav-tabs mb-3" id="structureTabs" role="tablist">
            <li class="nav-item" role="presentation">
                <button class="nav-link active" id="depts-tab" data-bs-toggle="tab" data-bs-target="#depts" type="button" role="tab">Подразделения</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="positions-tab" data-bs-toggle="tab" data-bs-target="#positions" type="button" role="tab">Должности</button>
            </li>
        </ul>

        <div class="tab-content" id="structureTabsContent">
            <div class="tab-pane fade show active" id="depts" role="tabpanel">
                <iframe src="/departments?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="positions" role="tabpanel">
                <iframe src="/positions?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

echo "🔧 Добавляем маршруты в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Добавляем маршруты для /ppe и /structure, если их нет
if '/ppe' not in content:
    route_ppe = '''
@app.get("/ppe", response_class=HTMLResponse)
async def ppe_tabs_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe/tabs.html",
        context={"title": "Управление СИЗ"},
    )
'''
    content += route_ppe
    print("✅ Маршрут /ppe добавлен.")

if '/structure' not in content:
    route_structure = '''
@app.get("/structure", response_class=HTMLResponse)
async def structure_tabs_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="structure/tabs.html",
        context={"title": "Структура"},
    )
'''
    content += route_structure
    print("✅ Маршрут /structure добавлен.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🔧 Обновляем навбар (ссылки на /ppe и /structure)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Меняем ссылки в навбаре
content = content.replace(
    'href="/ppe-items">',
    'href="/ppe">'
)
content = content.replace(
    'href="/departments">',
    'href="/structure">'
)

# Меняем активный класс для СИЗ и Структуры
content = content.replace(
    "{% if '/ppe-' in request.url.path or '/norms' in request.url.path or '/units' in request.url.path %}active{% endif %}",
    "{% if '/ppe' in request.url.path or '/norms' in request.url.path or '/units' in request.url.path %}active{% endif %}"
)
content = content.replace(
    "{% if '/departments' in request.url.path or '/positions' in request.url.path %}active{% endif %}",
    "{% if '/structure' in request.url.path or '/departments' in request.url.path or '/positions' in request.url.path %}active{% endif %}"
)

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Ссылки в навбаре обновлены (на /ppe и /structure).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Страницы с вкладками созданы."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add tabbed wrapper pages for PPE and Structure (via iframe)"
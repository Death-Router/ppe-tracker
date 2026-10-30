#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Восстанавливаем маршруты для страниц функций и размерных групп..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Добавляем маршруты, если их нет
if '/ppe-functions' not in content:
    route_func = '''
@app.get("/ppe-functions", response_class=HTMLResponse)
async def ppe_functions_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_functions/list.html",
        context={"title": "Функции СИЗ"},
    )
'''
    content += route_func
    print("✅ Маршрут /ppe-functions добавлен.")

if '/ppe-size-groups' not in content:
    route_groups = '''
@app.get("/ppe-size-groups", response_class=HTMLResponse)
async def ppe_size_groups_page(request: Request):
    redirect = check_auth(request)
    if redirect: return redirect
    return templates.TemplateResponse(
        request=request,
        name="ppe_size_groups/list.html",
        context={"title": "Размерные группы"},
    )
'''
    content += route_groups
    print("✅ Маршрут /ppe-size-groups добавлен.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Маршруты восстановлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: restore HTML routes for ppe-functions and ppe-size-groups"
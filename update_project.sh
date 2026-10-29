#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Меняем корневой маршрут (/) на редирект к сотрудникам..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Находим старый маршрут "/"
old_root = '''@app.get("/")
async def root():
    return {"message": "Привет! Сервер учета СИЗ работает."}'''

new_root = '''@app.get("/")
async def root():
    # Перенаправляем на список сотрудников
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/employees")'''

if old_root in content:
    content = content.replace(old_root, new_root)
    print("✅ Корневой маршрут изменен на редирект.")
else:
    print("⚠️ Не удалось найти старый маршрут '/'. Возможно, он уже изменен или выглядит иначе.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: redirect root path to employees list"
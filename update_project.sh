#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Возвращаем навбар на всех страницах (кроме iframe)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Убираем сложное условие, оставляем только проверку query_params
old_condition = '{% if not request.query_params.get("embedded") and "/ppe" not in (request.headers.get("referer") or "") and "/structure" not in (request.headers.get("referer") or "") %}'
new_condition = '{% if not request.query_params.get("embedded") %}'

if old_condition in content:
    content = content.replace(old_condition, new_condition)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Условие упрощено (только embedded=1).")
else:
    print("⚠️ Не удалось найти условие. Возможно, оно уже изменено.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навбар вернулся."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: restore navbar on main pages (hide only for embedded=1)"
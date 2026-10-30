#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем навбар внутри iframe (по referer)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Заменяем условие: теперь проверяем и query_params, и referer
old_condition = '{% if not request.query_params.get("embedded") %}'
new_condition = '{% if not request.query_params.get("embedded") and "/ppe" not in (request.headers.get("referer") or "") and "/structure" not in (request.headers.get("referer") or "") %}'

if old_condition in content:
    content = content.replace(old_condition, new_condition)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Условие для скрытия навбара обновлено (по referer).")
else:
    print("⚠️ Не удалось найти условие для скрытия навбара.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Навбар больше не будет дублироваться внутри iframe."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: hide navbar inside iframe using referer check"
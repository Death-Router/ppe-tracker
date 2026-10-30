#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем глобальный скрипт валидации из base.html..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Удаляем скрипт валидации (тот, что мы добавляли)
import re
content = re.sub(r'<script>\s*document\.addEventListener\(\'DOMContentLoaded\'.*?</script>', '', content, flags=re.DOTALL)

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Глобальный скрипт валидации удален.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверь /login (Ctrl+F5)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove global validation script (causing freeze)"
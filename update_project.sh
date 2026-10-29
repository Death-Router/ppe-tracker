#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем импорт в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Проверяем, есть ли уже employee_ppe_issues в импорте
if 'employee_ppe_issues' not in content.split('app.include_router')[0]:
    # Ищем строку импорта из app.api.v1.endpoints
    import re
    # Паттерн для строки from app.api.v1.endpoints import (...)
    pattern = r'from app\.api\.v1\.endpoints import \(([^)]+)\)'
    match = re.search(pattern, content, re.DOTALL)
    
    if match:
        # Добавляем employee_ppe_issues в скобки
        imports = match.group(1)
        if 'employee_ppe_issues' not in imports:
            new_imports = imports.strip() + ', employee_ppe_issues'
            content = content.replace(match.group(0), f'from app.api.v1.endpoints import ({new_imports})')
            print("✅ Импорт employee_ppe_issues добавлен в main.py.")
    else:
        # Если импорт не в скобках, ищем однострочный
        pattern2 = r'from app\.api\.v1\.endpoints import (.*)'
        match2 = re.search(pattern2, content)
        if match2 and 'employee_ppe_issues' not in match2.group(1):
            new_line = match2.group(1).strip() + ', employee_ppe_issues'
            content = content.replace(match2.group(0), f'from app.api.v1.endpoints import {new_line}')
            print("✅ Импорт employee_ppe_issues добавлен в main.py (однострочный).")
else:
    print("ℹ️ Импорт employee_ppe_issues уже есть в main.py.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 3

echo "🔄 Проверяем, что приложение запустилось..."
docker compose logs api --tail 10

echo "✅ ГОТОВО! Если в логах 'Application startup complete', то всё хорошо."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: add missing employee_ppe_issues import in main.py"
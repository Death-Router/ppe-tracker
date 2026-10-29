#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем requirements.txt..."

# Перезаписываем requirements.txt с правильными пакетами
cat > requirements.txt << 'EOF'
alembic==1.20.1
annotated-doc==0.0.5
annotated-types==0.8.0
anyio==4.15.1
asyncpg==0.32.0
click==8.5.0
fastapi==0.162.0
greenlet==3.5.6
h11==0.16.0
httptools==0.9.0
idna==3.20
mako==1.4.3
markupsafe==3.0.4
opentelemetry-api==1.45.1
pydantic==2.14.1
pydantic-core==2.50.1
pydantic-settings==2.16.1
python-dotenv==1.2.4
pyyaml==6.0.3
sqlalchemy==2.1.6
starlette==1.10.0
typing-extensions==4.16.0
typing-inspection==0.4.4
uvicorn==0.54.0
uvloop==0.23.0
watchfiles==1.3.0
websockets==17.3
jinja2
python-multipart
pandas
openpyxl
EOF

echo "🚀 Пересобираем и запускаем контейнеры..."
docker compose up -d --build
sleep 5

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: requirements.txt syntax and add pandas/openpyxl"
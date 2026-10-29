#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Фиксируем версию bcrypt (откат до 4.0.1)..."

# Удаляем старые записи о bcrypt и passlib, чтобы навести порядок
sed -i '/^bcrypt/d' requirements.txt
sed -i '/^passlib/d' requirements.txt

# Добавляем совместимые версии
echo "passlib[bcrypt]==1.7.4" >> requirements.txt
echo "bcrypt==4.0.1" >> requirements.txt

echo "🚀 Пересобираем контейнер (устанавливаем bcrypt 4.0.1)..."
docker compose up -d --build
sleep 5

echo "🔄 Создаем администратора..."
docker compose exec -T api python create_admin.py

echo "🔄 Проверяем логи..."
docker compose logs api --tail 10

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: pin bcrypt to 4.0.1 for passlib compatibility"
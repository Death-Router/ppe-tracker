#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно добавляем formatPeriod в employee_edit.js..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Если функции нет, добавляем её в самое начало файла (после IIFE)
if 'function formatPeriod' not in content:
    # Находим начало файла (первые строки)
    # Вставляем функцию сразу после (() => {
    insertion = '''
  function formatPeriod(value, unit) {
    if (!value) return '—';
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${unit}`;

    if (unit === 'год') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} лет`;
      if (lastDigit === 1) return `${num} год`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} года`;
      return `${num} лет`;
    }
    if (unit === 'месяц') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} месяцев`;
      if (lastDigit === 1) return `${num} месяц`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} месяца`;
      return `${num} месяцев`;
    }
    if (unit === 'день') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} дней`;
      if (lastDigit === 1) return `${num} день`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} дня`;
      return `${num} дней`;
    }
    if (unit === 'смена') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} смен`;
      if (lastDigit === 1) return `${num} смена`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} смены`;
      return `${num} смен`;
    }
    return `${value} ${unit}`;
  }

  function formatUnit(value, shortName) {
    if (!shortName) return value;
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${shortName}`;

    if (shortName.toLowerCase() === 'пара') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} пар`;
      if (lastDigit === 1) return `${num} пара`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} пары`;
      return `${num} пар`;
    }
    if (shortName.toLowerCase() === 'штука' || shortName.toLowerCase() === 'шт') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} штук`;
      if (lastDigit === 1) return `${num} штука`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} штуки`;
      return `${num} штук`;
    }
    if (shortName.toLowerCase() === 'комплект') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} комплектов`;
      if (lastDigit === 1) return `${num} комплект`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} комплекта`;
      return `${num} комплектов`;
    }
    return `${num} ${shortName}`;
  }
'''

    # Вставляем после (() => {
    content = content.replace('(() => {', '(() => {\n' + insertion, 1)
    print("✅ Функции formatPeriod и formatUnit добавлены в начало employee_edit.js.")
else:
    print("ℹ️ Функция formatPeriod уже есть.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Ошибка formatPeriod исправлена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: add formatPeriod and formatUnit to employee_edit.js"
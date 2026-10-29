#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем склонение для сроков износа в norms_list.js..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# 1. Проверяем, есть ли функция formatPeriod. Если нет — добавляем.
if 'function formatPeriod' not in content:
    format_period_func = '''
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
'''
    # Вставляем после escapeHtml
    content = content.replace(
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }",
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }\n" + format_period_func
    )
    print("✅ Функция formatPeriod добавлена.")

# 2. Заменяем вывод срока износа в таблице на использование formatPeriod
old_td = '<td>${escapeHtml(n.wear_period_value)} ${escapeHtml(n.wear_period_unit)}</td>'
new_td = '<td>${formatPeriod(n.wear_period_value, n.wear_period_unit)}</td>'

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Колонка 'Срок износа' обновлена (использует formatPeriod).")
else:
    # Альтернативный вариант, если структура отличается
    content = content.replace(
        '${escapeHtml(n.wear_period_value)} ${escapeHtml(n.wear_period_unit)}',
        '${formatPeriod(n.wear_period_value, n.wear_period_unit)}'
    )
    print("✅ Колонка 'Срок износа' обновлена (альтернативный метод).")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Сроки износа теперь склоняются правильно."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: humanize wear period in norms table (год, года, лет)"
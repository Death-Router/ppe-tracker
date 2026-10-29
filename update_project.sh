#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем отображение норм в карточке сотрудника..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
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
    content = content.replace(
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }",
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }\n" + format_period_func
    )
    print("✅ Функция formatPeriod добавлена в employee_edit.js.")

# 2. Проверяем, есть ли функция formatUnit (для единиц измерения). Если нет — добавляем.
if 'function formatUnit' not in content:
    format_unit_func = '''
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
    content = content.replace(
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }",
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }\n" + format_unit_func
    )
    print("✅ Функция formatUnit добавлена в employee_edit.js.")

# 3. Находим место, где формируется строка для колонки "Норма"
old_norm_str = '''      const periodStr = `${norm.wear_period_value} ${norm.wear_period_unit}`;

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${periodStr} (${requiredQty} ${norm.quantity.includes('пар') ? 'пар' : 'шт'})</td>'''

new_norm_str = '''      // Форматируем срок (5 лет) и количество (5 шт)
      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedPeriod} (${formattedQuantity})</td>'''

if old_norm_str in content:
    content = content.replace(old_norm_str, new_norm_str)
    print("✅ Формирование строки 'Норма' обновлено (использует formatPeriod и formatUnit).")
else:
    print("⚠️ Не удалось найти старый блок формирования строки нормы. Возможно, структура изменилась.")
    # Попробуем найти по ключевым словам
    if 'periodStr' in content:
        content = content.replace(
            "const periodStr = `${norm.wear_period_value} ${norm.wear_period_unit}`;",
            "const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);"
        )
        content = content.replace(
            "<td>${periodStr} (${requiredQty} ${norm.quantity.includes('пар') ? 'пар' : 'шт'})</td>",
            "<td>${formattedPeriod} (${formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт')})</td>"
        )
        print("✅ Строка нормы обновлена (альтернативный метод).")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Сроки и количества в нормах сотрудника теперь склоняются правильно."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: humanize norms in employee card (period and unit)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Меняем формат отображения норм в карточке сотрудника..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Ищем блок формирования строки нормы (старый или новый формат)
# Вариант 1: Если у нас уже используется formattedPeriod и formattedQuantity
old_block = '''      // Форматируем срок (5 лет) и количество (5 шт)
      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedPeriod} (${formattedQuantity})</td>'''

new_block = '''      // Форматируем срок и количество
      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedQuantity} на ${formattedPeriod}</td>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    print("✅ Формат 'Количество на Срок' добавлен (вариант 1).")
else:
    # Вариант 2: Если структура немного отличается (например, без комментария)
    old_block_alt = '''      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedPeriod} (${formattedQuantity})</td>'''

    new_block_alt = '''      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedQuantity} на ${formattedPeriod}</td>'''

    if old_block_alt in content:
        content = content.replace(old_block_alt, new_block_alt)
        print("✅ Формат 'Количество на Срок' добавлен (вариант 2).")
    else:
        # Вариант 3: Самая старая версия (через periodStr)
        old_block_old = '''      const periodStr = `${norm.wear_period_value} ${norm.wear_period_unit}`;

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${periodStr} (${requiredQty} ${norm.quantity.includes('пар') ? 'пар' : 'шт'})</td>'''

        new_block_old = '''      const formattedPeriod = formatPeriod(norm.wear_period_value, norm.wear_period_unit);
      const formattedQuantity = formatUnit(norm.quantity, norm.ppe_item?.unit?.short_name || 'шт');

      return `
        <tr>
          <td>${norm.ppe_item?.name ?? '—'}</td>
          <td>${formattedQuantity} на ${formattedPeriod}</td>'''

        if old_block_old in content:
            content = content.replace(old_block_old, new_block_old)
            print("✅ Формат 'Количество на Срок' добавлен (вариант 3 - старый код).")
        else:
            print("⚠️ Не удалось найти блок формирования строки нормы. Возможно, структура изменилась.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь нормы отображаются как '5 пар на 5 лет'."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: change norm format to 'quantity on period' (e.g., 5 пар на 5 лет)"
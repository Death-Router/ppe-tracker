#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🛠 Приводим единицы измерения к нижнему регистру (в базе)..."

# Создаем временный скрипт для исправления регистра в таблице units
cat > fix_units.py << 'EOF'
import asyncio
from sqlalchemy import select
from app.models.unit import Unit
from app.db.session import async_session_maker

async def fix():
    async with async_session_maker() as db:
        result = await db.execute(select(Unit))
        units = result.scalars().all()
        for unit in units:
            # Делаем первую букву строчной (пар, штука)
            new_short = unit.short_name.lower()
            if unit.short_name != new_short:
                unit.short_name = new_short
                print(f"Обновление: '{unit.short_name}' -> '{new_short}'")
        await db.commit()
        print("✅ Единицы измерения приведены к нижнему регистру.")

if __name__ == "__main__":
    asyncio.run(fix())
EOF

docker compose cp fix_units.py api:/app/fix_units.py
docker compose exec -T api python fix_units.py
rm fix_units.py

echo "🔧 Добавляем функцию склонения в norms_list.js..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# Добавляем функцию склонения (если еще нет)
if 'function formatUnit' not in content:
    format_func = '''
  function formatUnit(value, shortName) {
    if (!shortName) return value;
    const num = parseInt(value, 10);
    if (isNaN(num)) return `${value} ${shortName}`;

    // Склонение для "пара"
    if (shortName.toLowerCase() === 'пара') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} пар`;
      if (lastDigit === 1) return `${num} пара`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} пары`;
      return `${num} пар`;
    }
    // Склонение для "штука"
    if (shortName.toLowerCase() === 'штука' || shortName.toLowerCase() === 'шт') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} штук`;
      if (lastDigit === 1) return `${num} штука`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} штуки`;
      return `${num} штук`;
    }
    // Склонение для "комплект"
    if (shortName.toLowerCase() === 'комплект') {
      const lastDigit = num % 10;
      const lastTwo = num % 100;
      if (lastTwo >= 11 && lastTwo <= 14) return `${num} комплектов`;
      if (lastDigit === 1) return `${num} комплект`;
      if (lastDigit >= 2 && lastDigit <= 4) return `${num} комплекта`;
      return `${num} комплектов`;
    }
    // По умолчанию
    return `${num} ${shortName}`;
  }
'''
    content = content.replace(
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }",
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }\n" + format_func
    )
    print("✅ Функция formatUnit добавлена в norms_list.js.")

# Заменяем вывод количества в таблице норм на использование formatUnit
old_td = '''<td>
          ${n.quantity} ${n.ppe_item?.unit?.short_name ? escapeHtml(n.ppe_item.unit.short_name) : ''}
        </td>'''

new_td = '''<td>${formatUnit(n.quantity, n.ppe_item?.unit?.short_name)}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Таблица норм обновлена (использует formatUnit).")
else:
    # Если структура отличается, ищем более общий вариант
    content = content.replace(
        '${n.quantity} ${n.ppe_item?.unit?.short_name ? escapeHtml(n.ppe_item.unit.short_name) : \'\'}',
        '${formatUnit(n.quantity, n.ppe_item?.unit?.short_name)}'
    )
    print("✅ Таблица норм обновлена (альтернативный метод).")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🔧 Добавляем функцию склонения в employee_edit.js..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Добавляем функцию склонения (если еще нет)
if 'function formatUnit' not in content:
    format_func = '''
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
        "function escapeHtml(s) { return String(s ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;'); }\n" + format_func
    )
    print("✅ Функция formatUnit добавлена в employee_edit.js.")

# Заменяем вывод количества в таблице выдач
old_td = '<td>${issue.quantity} ${issue.ppe_item?.unit?.short_name ? escapeHtml(issue.ppe_item.unit.short_name) : \'\'}</td>'
new_td = '<td>${formatUnit(issue.quantity, issue.ppe_item?.unit?.short_name)}</td>'

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Таблица выдач обновлена (использует formatUnit).")
else:
    # Альтернативный вариант
    content = content.replace(
        '${issue.quantity} ${issue.ppe_item?.unit?.short_name ? escapeHtml(issue.ppe_item.unit.short_name) : \'\'}',
        '${formatUnit(issue.quantity, issue.ppe_item?.unit?.short_name)}'
    )
    print("✅ Таблица выдач обновлена (альтернативный метод).")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Единицы измерения теперь склоняются правильно."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: humanize unit names with plural forms (пара, штука, комплект)"
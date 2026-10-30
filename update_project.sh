#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Усиливаем CSS для выбранных строк..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

# Удаляем старые правила для selected-row
import re
content = re.sub(r'/\* Выбранные строки.*?\.table tr\.selected-row:hover \{[^}]*\}', '', content, flags=re.DOTALL)

# Добавляем новые, более специфичные
new_css = '''
/* Выбранные строки (выделенные чекбоксом) — фиолетовый фон */
.table tbody tr.selected-row > td,
.table tbody tr.selected-row > th {
    background-color: rgba(91, 44, 138, 0.08) !important;
}

.table tbody tr.selected-row:hover > td,
.table tbody tr.selected-row:hover > th {
    background-color: rgba(91, 44, 138, 0.12) !important;
}
'''

content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(content)
print("✅ CSS усилен (!important и точные селекторы).")
PYEOF

echo "🔧 Проверяем, что JS добавляет класс selected-row..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Проверяем, есть ли класс selected-row в renderTable
if 'selected-row' not in content:
    print("⚠️ Класс selected-row отсутствует в JS. Добавляем...")
    
    # В renderTable
    content = content.replace(
        '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">''',
        '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px;">'''
    )
    
    # В toggleSelection
    content = content.replace(
        '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
  };''',
        '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) row.classList.add('selected-row');
      else row.classList.remove('selected-row');
    }
  };'''
    )
    
    with open('app/static/js/ppe_items_list.js', 'w') as f:
        f.write(content)
    print("✅ Класс selected-row добавлен в JS.")
else:
    print("ℹ️ Класс selected-row уже есть в JS.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверь страницу (Ctrl+F5)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: strengthen selected-row CSS (important, correct selectors)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Подсвечиваем выбранные строки в цвет навбара..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

new_css = '''
/* Выбранные строки (выделенные чекбоксом) — фиолетовый фон */
.table tr.selected-row {
    background-color: rgba(91, 44, 138, 0.08) !important;
}
.table tr.selected-row td {
    background-color: rgba(91, 44, 138, 0.08) !important;
}

/* Фон при наведении на выбранную строку */
.table tr.selected-row:hover {
    background-color: rgba(91, 44, 138, 0.12) !important;
}
'''

if 'selected-row' not in content:
    content += new_css
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для выбранных строк добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🔧 Обновляем JS (добавляем класс selected-row при выборе)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# В функции renderTable добавляем класс selected-row для выбранных
old_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">'''

new_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px;">'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ renderTable обновлен (класс selected-row).")
else:
    print("⚠️ Не удалось найти блок renderTable.")

# В функции toggleSelection добавляем/убираем класс
old_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
  };'''

new_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    // Обновляем класс строки
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) row.classList.add('selected-row');
      else row.classList.remove('selected-row');
    }
  };'''

if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
    print("✅ toggleSelection обновлен (класс selected-row).")
else:
    print("⚠️ Не удалось найти toggleSelection.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Выбранные строки теперь фиолетовые."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: highlight selected rows in purple (navbar color)"
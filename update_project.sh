#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно обновляем ppe_items_list.js (класс selected-row)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# 1. В renderTable добавляем класс selected-row
old_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      return `
      <tr data-item-id="${i.id}" style="height: 40px;">'''

new_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px;">'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ renderTable обновлен.")
else:
    print("⚠️ Не удалось найти старый renderTable.")

# 2. В toggleSelection добавляем/убираем класс
old_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
  };'''

new_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) row.classList.add('selected-row');
      else row.classList.remove('selected-row');
    }
  };'''

if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
    print("✅ toggleSelection обновлен.")
else:
    print("⚠️ Не удалось найти старый toggleSelection.")

# 3. В selectAllCheckbox (если есть) тоже обновляем классы
old_select_all = '''      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
      });'''

new_select_all = '''      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
        
        const row = document.querySelector(`tr[data-item-id="${id}"]`);
        if (row) {
          if (checked) row.classList.add('selected-row');
          else row.classList.remove('selected-row');
        }
      });'''

if old_select_all in content:
    content = content.replace(old_select_all, new_select_all)
    print("✅ selectAllCheckbox обновлен.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Класс selected-row добавлен."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force add selected-row class to table rows"
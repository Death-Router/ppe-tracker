#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем подсветку выбранных строк (меняем фон ячеек, а не строки)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# 1. В renderTable добавляем фон для ячеек (если выбрано)
old_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      const bgStyle = selectedIds.has(i.id) ? 'background-color: rgba(91, 44, 138, 0.08);' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px; ${bgStyle}">
        <td class="py-1">
          <input type="checkbox" class="item-checkbox" value="${i.id}" ${isChecked} onchange="toggleSelection(${i.id}, this.checked)">
        </td>'''

new_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px;">
        <td class="py-1">
          <input type="checkbox" class="item-checkbox" value="${i.id}" ${isChecked} onchange="toggleSelection(${i.id}, this.checked)">
        </td>'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ renderTable обновлен (убран style с tr).")

# 2. В toggleSelection меняем фон у всех ячеек
old_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) {
        row.style.backgroundColor = 'rgba(91, 44, 138, 0.08)';
        row.classList.add('selected-row');
      } else {
        row.style.backgroundColor = '';
        row.classList.remove('selected-row');
      }
    }
  };'''

new_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      const cells = row.querySelectorAll('td');
      if (checked) {
        row.classList.add('selected-row');
        cells.forEach(td => td.style.backgroundColor = 'rgba(91, 44, 138, 0.08)');
      } else {
        row.classList.remove('selected-row');
        cells.forEach(td => td.style.backgroundColor = '');
      }
    }
  };'''

if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
    print("✅ toggleSelection обновлен (меняем фон ячеек).")

# 3. В selectAllCheckbox тоже меняем фон у всех ячеек
old_select_all = '''      document.querySelectorAll('.item-checkbox').forEach(cb => {
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

new_select_all = '''      document.querySelectorAll('.item-checkbox').forEach(cb => {
        cb.checked = checked;
        const id = Number(cb.value);
        if (checked) selectedIds.add(id);
        else selectedIds.delete(id);
        
        const row = document.querySelector(`tr[data-item-id="${id}"]`);
        if (row) {
          const cells = row.querySelectorAll('td');
          if (checked) {
            row.classList.add('selected-row');
            cells.forEach(td => td.style.backgroundColor = 'rgba(91, 44, 138, 0.08)');
          } else {
            row.classList.remove('selected-row');
            cells.forEach(td => td.style.backgroundColor = '');
          }
        }
      });'''

if old_select_all in content:
    content = content.replace(old_select_all, new_select_all)
    print("✅ selectAllCheckbox обновлен (меняем фон ячеек).")

# 4. Убедимся, что CSS для .selected-row тоже меняет фон ячеек
with open('app/static/css/app.css', 'r') as f:
    css_content = f.read()

# Удаляем старые правила для selected-row
import re
css_content = re.sub(r'/\* Выбранные строки.*?\.table tbody tr\.selected-row:hover > th \{[^}]*\}', '', css_content, flags=re.DOTALL)

# Добавляем новые
new_css = '''
/* Выбранные строки (выделенные чекбоксом) — фиолетовый фон ячеек */
.table tbody tr.selected-row > td {
    background-color: rgba(91, 44, 138, 0.08) !important;
}
.table tbody tr.selected-row:hover > td {
    background-color: rgba(91, 44, 138, 0.12) !important;
}
'''

css_content += new_css

with open('app/static/css/app.css', 'w') as f:
    f.write(css_content)
print("✅ CSS для selected-row обновлен (ячейки).")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Подсветка должна стать фиолетовой."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: highlight selected rows by changing cell background (purple)"
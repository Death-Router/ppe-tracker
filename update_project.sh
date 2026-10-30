#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно подсвечиваем выбранные строки (через style)..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# Заменяем toggleSelection на версию с явным изменением фона
old_toggle = '''  window.toggleSelection = (id, checked) => {
    if (checked) selectedIds.add(id);
    else selectedIds.delete(id);
    updateBulkPanel();
    
    const row = document.querySelector(`tr[data-item-id="${id}"]`);
    if (row) {
      if (checked) row.classList.add('selected-row');
      else row.classList.remove('selected-row');
    }
  };'''

new_toggle = '''  window.toggleSelection = (id, checked) => {
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

if old_toggle in content:
    content = content.replace(old_toggle, new_toggle)
    print("✅ toggleSelection обновлен (явный фон).")
else:
    print("⚠️ Не удалось найти toggleSelection. Возможно, структура изменилась.")

# Также при отрисовке таблицы (renderTable) устанавливаем фон для выбранных
old_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px;">'''

new_render = '''      const isChecked = selectedIds.has(i.id) ? 'checked' : '';
      const rowClass = selectedIds.has(i.id) ? 'selected-row' : '';
      const bgStyle = selectedIds.has(i.id) ? 'background-color: rgba(91, 44, 138, 0.08);' : '';
      return `
      <tr data-item-id="${i.id}" class="${rowClass}" style="height: 40px; ${bgStyle}">'''

if old_render in content:
    content = content.replace(old_render, new_render)
    print("✅ renderTable обновлен (явный фон).")
else:
    print("⚠️ Не удалось найти старый renderTable.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Выбранные строки будут подсвечены фиолетовым."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force highlight selected rows via inline style"
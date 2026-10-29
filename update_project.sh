#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем сортировку по алфавиту в ppe_categories_list.js..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_categories_list.js', 'r') as f:
    content = f.read()

# В функции filterCategories добавляем сортировку перед рендером
old_code = '''    if (searchTerm) {
      filtered = filtered.filter(c => 
        c.name.toLowerCase().includes(searchTerm) || 
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }

    renderTable(filtered);'''

new_code = '''    if (searchTerm) {
      filtered = filtered.filter(c => 
        c.name.toLowerCase().includes(searchTerm) || 
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }

    // Сортировка по алфавиту (по названию)
    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));

    renderTable(filtered);'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Сортировка по алфавиту добавлена в JS.")
else:
    print("⚠️ Не удалось найти блок filterCategories для добавления сортировки.")

with open('app/static/js/ppe_categories_list.js', 'w') as f:
    f.write(content)
PYEOF

# То же самое для списка СИЗ (наименований)
echo "🔧 Добавляем сортировку по алфавиту в ppe_items_list.js..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# В функции filterItems добавляем сортировку перед рендером
old_code = '''    if (selectedCategory) {
      filtered = filtered.filter(item => item.category?.name === selectedCategory);
    }

    renderTable(filtered);'''

new_code = '''    if (selectedCategory) {
      filtered = filtered.filter(item => item.category?.name === selectedCategory);
    }

    // Сортировка по алфавиту (по названию)
    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));

    renderTable(filtered);'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Сортировка по алфавиту добавлена в ppe_items_list.js.")
else:
    print("⚠️ Не удалось найти блок filterItems для добавления сортировки.")

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add alphabetical sorting to categories and ppe items lists"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Добавляем фильтры по функциям и размерным группам..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Добавляем фильтры в панель поиска
old_search = '''<!-- Панель поиска и фильтрации -->
<div class="row g-2 mb-3">
    <div class="col-md-5">
        <div class="input-group">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
        </div>
    </div>
</div>'''

new_search = '''<!-- Панель поиска и фильтрации -->
<div class="row g-2 mb-3">
    <div class="col-md-4">
        <div class="input-group">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
        </div>
    </div>
    <div class="col-md-4">
        <select class="form-select" id="filter-function">
            <option value="">Все функции</option>
        </select>
    </div>
    <div class="col-md-4">
        <select class="form-select" id="filter-size-group">
            <option value="">Все размерные группы</option>
        </select>
    </div>
</div>'''

if old_search in content:
    content = content.replace(old_search, new_search)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Фильтры добавлены в шаблон.")
else:
    print("⚠️ Не удалось найти панель поиска в шаблоне.")
PYEOF

echo "📝 Обновляем JS для фильтрации..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_items_list.js', 'r') as f:
    content = f.read()

# 1. Добавляем переменные для фильтров
if 'filterFunction' not in content:
    content = content.replace(
        "  const searchInput = document.getElementById('search-input');",
        "  const searchInput = document.getElementById('search-input');\n  const filterFunction = document.getElementById('filter-function');\n  const filterSizeGroup = document.getElementById('filter-size-group');"
    )

# 2. В loadSelects заполняем фильтры
old_load = '''      const functions = await API.get('/api/v1/ppe_functions');
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      bulkFunctionSelect.innerHTML = '<option value="">-- Функция СИЗ --</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');'''

new_load = '''      const functions = await API.get('/api/v1/ppe_functions');
      createFunctionSelect.innerHTML = '<option value="">Не указана</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      bulkFunctionSelect.innerHTML = '<option value="">-- Функция СИЗ --</option>' +
        functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      if (filterFunction) {
        filterFunction.innerHTML = '<option value="">Все функции</option>' +
          functions.map(f => `<option value="${f.id}">${escapeHtml(f.name)}</option>`).join('');
      }'''

if old_load in content:
    content = content.replace(old_load, new_load)

# 3. В loadSelects заполняем фильтр размерных групп
old_groups = '''      const groups = await API.get('/api/v1/ppe_size_groups');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      bulkSizeGroupSelect.innerHTML = '<option value="">-- Размерная группа --</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');'''

new_groups = '''      const groups = await API.get('/api/v1/ppe_size_groups');
      createSizeGroupSelect.innerHTML = '<option value="">Не указана</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      bulkSizeGroupSelect.innerHTML = '<option value="">-- Размерная группа --</option>' +
        groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      if (filterSizeGroup) {
        filterSizeGroup.innerHTML = '<option value="">Все размерные группы</option>' +
          groups.map(g => `<option value="${g.id}">${escapeHtml(g.name)}</option>`).join('');
      }'''

if old_groups in content:
    content = content.replace(old_groups, new_groups)

# 4. Обновляем filterItems (добавляем фильтрацию по функции и группе)
old_filter = '''  function filterItems() {
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.function?.name || '').toLowerCase().includes(searchTerm) ||
        (item.size_group?.name || '').toLowerCase().includes(searchTerm)
      );
    }

    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));
    renderTable(filtered);
  }'''

new_filter = '''  function filterItems() {
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const funcId = filterFunction ? Number(filterFunction.value) : null;
    const groupId = filterSizeGroup ? Number(filterSizeGroup.value) : null;

    let filtered = allItems;

    if (searchTerm) {
      filtered = filtered.filter(item => 
        item.name.toLowerCase().includes(searchTerm) || 
        (item.function?.name || '').toLowerCase().includes(searchTerm) ||
        (item.size_group?.name || '').toLowerCase().includes(searchTerm)
      );
    }

    if (funcId) {
      filtered = filtered.filter(item => item.function_id === funcId);
    }

    if (groupId) {
      filtered = filtered.filter(item => item.size_group_id === groupId);
    }

    filtered.sort((a, b) => a.name.localeCompare(b.name, 'ru'));
    renderTable(filtered);
  }'''

if old_filter in content:
    content = content.replace(old_filter, new_filter)

# 5. Добавляем обработчики для фильтров
old_listener = "  if (searchInput) searchInput.addEventListener('input', filterItems);"
new_listener = "  if (searchInput) searchInput.addEventListener('input', filterItems);\n  if (filterFunction) filterFunction.addEventListener('change', filterItems);\n  if (filterSizeGroup) filterSizeGroup.addEventListener('change', filterItems);"

if old_listener in content:
    content = content.replace(old_listener, new_listener)

with open('app/static/js/ppe_items_list.js', 'w') as f:
    f.write(content)
print("✅ JS обновлен (фильтры по функциям и группам).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Фильтры добавлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add filters by function and size group in ppe_items list"
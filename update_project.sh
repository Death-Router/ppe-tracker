#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Переносим кнопку '+' к заголовку 'Наименования СИЗ'..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# 1. Убираем кнопку "+" из панели фильтров
old_filters = '''<!-- Панель фильтров и кнопка "Добавить" (CSS Grid) -->
<div class="mb-3" style="display: grid; grid-template-columns: 300px 1fr 1fr auto; gap: 8px; align-items: center;">
    <div class="input-group">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    <select class="form-select" id="filter-function">
        <option value="">Все функции</option>
    </select>
    <select class="form-select" id="filter-size-group">
        <option value="">Все размерные группы</option>
    </select>
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>'''

new_filters = '''<!-- Панель фильтров (без кнопки "Добавить") -->
<div class="mb-3" style="display: grid; grid-template-columns: 300px 1fr 1fr; gap: 8px; align-items: center;">
    <div class="input-group">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    <select class="form-select" id="filter-function">
        <option value="">Все функции</option>
    </select>
    <select class="form-select" id="filter-size-group">
        <option value="">Все размерные группы</option>
    </select>
</div>'''

if old_filters in content:
    content = content.replace(old_filters, new_filters)
    print("✅ Кнопка '+' убрана из панели фильтров.")
else:
    print("⚠️ Не удалось найти панель фильтров.")

# 2. Добавляем кнопку "+" рядом с заголовком
old_header = '''<!-- Заголовок и счетчик выбранных -->
<div class="d-flex align-items-center gap-3 flex-wrap mb-3">
    <h1 class="h3 mb-0">Наименования СИЗ</h1>
    
    <!-- Блок массовых операций (появляется при выборе) -->
    <div id="bulk-actions" class="d-flex align-items-center gap-2 d-none">
        <span class="badge bg-secondary">Выбрано: <span id="selected-count">0</span></span>
        <button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-1" onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>
        <button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>
    </div>
</div>'''

new_header = '''<!-- Заголовок, кнопка "Добавить" и счетчик выбранных -->
<div class="d-flex align-items-center gap-3 flex-wrap mb-3">
    <div class="d-flex align-items-center gap-2">
        <button class="btn btn-success btn-sm" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
        <h1 class="h3 mb-0">Наименования СИЗ</h1>
    </div>
    
    <!-- Блок массовых операций (появляется при выборе) -->
    <div id="bulk-actions" class="d-flex align-items-center gap-2 d-none">
        <span class="badge bg-secondary">Выбрано: <span id="selected-count">0</span></span>
        <button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-1" onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>
        <button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-1" onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>
    </div>
</div>'''

if old_header in content:
    content = content.replace(old_header, new_header)
    print("✅ Кнопка '+' добавлена слева от заголовка.")
else:
    print("⚠️ Не удалось найти блок заголовка.")

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка '+' теперь рядом с заголовком."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: move add button to header next to title in ppe_items list"
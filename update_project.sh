#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Выравниваем панель фильтров и кнопок массовых операций..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Находим блок с фильтрами и кнопками
old_block = '''<!-- Панель фильтров и массовых действий -->
<div class="d-flex align-items-center gap-2 mb-3 flex-wrap">
    <div class="input-group flex-grow-1" style="min-width: 200px; max-width: 300px;">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    
    <select class="form-select" id="filter-function" style="width: auto;">
        <option value="">Все функции</option>
    </select>
    
    <select class="form-select" id="filter-size-group" style="width: auto;">
        <option value="">Все размерные группы</option>
    </select>

    <div class="ms-auto d-flex gap-2">
        <span id="selected-count" class="align-self-center fw-bold me-2 d-none">Выбрано: <span>0</span></span>
        <button id="btn-bulk-edit" class="btn btn-outline-primary" disabled onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>
        <button id="btn-bulk-delete" class="btn btn-outline-danger" disabled onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>
    </div>
</div>'''

new_block = '''<!-- Панель фильтров и массовых действий -->
<div class="d-flex align-items-center gap-2 mb-3">
    <div class="input-group" style="min-width: 200px; max-width: 300px;">
        <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
        <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
    </div>
    
    <select class="form-select" id="filter-function" style="width: auto;">
        <option value="">Все функции</option>
    </select>
    
    <select class="form-select" id="filter-size-group" style="width: auto;">
        <option value="">Все размерные группы</option>
    </select>

    <div class="ms-auto d-flex align-items-center gap-2">
        <span id="selected-count" class="fw-bold me-2 d-none">Выбрано: <span>0</span></span>
        <button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-2" disabled onclick="openBulkEditModal()" title="Редактировать выбранные" style="height: 31px;"><i class="bi bi-pencil"></i></button>
        <button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-2" disabled onclick="bulkDelete()" title="Удалить выбранные" style="height: 31px;"><i class="bi bi-trash"></i></button>
    </div>
</div>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Панель выровнена (кнопки в одном ряду с фильтрами).")
else:
    print("⚠️ Не удалось найти блок фильтров для замены. Возможно, структура изменилась.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: align bulk action buttons with filters in one row"
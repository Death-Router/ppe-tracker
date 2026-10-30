#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Делаем панель фильтров с фиксированной сеткой (CSS Grid)..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Находим панель фильтров
old_filters = '''<!-- Панель фильтров и кнопка "Добавить" -->
<div class="d-flex align-items-center justify-content-between mb-3">
    <div class="d-flex align-items-center gap-2">
        <div class="input-group" style="width: 300px;">
            <span class="input-group-text bg-white"><i class="bi bi-search"></i></span>
            <input type="text" class="form-control" id="search-input" placeholder="Поиск по названию...">
        </div>
        <select class="form-select" id="filter-function" style="width: auto;">
            <option value="">Все функции</option>
        </select>
        <select class="form-select" id="filter-size-group" style="width: auto;">
            <option value="">Все размерные группы</option>
        </select>
    </div>
    
    <button class="btn btn-success" data-bs-toggle="modal" data-bs-target="#createModal" title="Добавить"><i class="bi bi-plus-lg"></i></button>
</div>'''

new_filters = '''<!-- Панель фильтров и кнопка "Добавить" (CSS Grid) -->
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

if old_filters in content:
    content = content.replace(old_filters, new_filters)
    with open('app/templates/ppe_items/list.html', 'w') as f:
        f.write(content)
    print("✅ Панель фильтров переведена на CSS Grid (300px / 1fr / 1fr / auto).")
else:
    print("⚠️ Не удалось найти панель фильтров для замены.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Панель фильтров теперь использует CSS Grid."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: use CSS Grid for filters panel in ppe_items list"
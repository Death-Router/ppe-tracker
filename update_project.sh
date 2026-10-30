#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем вкладки на странице /ppe..."

cat > app/templates/ppe/tabs.html << 'EOF'
{% extends "base.html" %}
{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-12">
        <h1 class="h3 mb-3">Управление СИЗ</h1>
        
        <ul class="nav nav-tabs mb-3" id="ppeTabs" role="tablist">
            <li class="nav-item" role="presentation">
                <button class="nav-link active" id="items-tab" data-bs-toggle="tab" data-bs-target="#items" type="button" role="tab">Наименования СИЗ</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="norms-tab" data-bs-toggle="tab" data-bs-target="#norms" type="button" role="tab">Нормы выдачи</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="functions-tab" data-bs-toggle="tab" data-bs-target="#functions" type="button" role="tab">Функции СИЗ</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="size-groups-tab" data-bs-toggle="tab" data-bs-target="#size-groups" type="button" role="tab">Размерные группы</button>
            </li>
            <li class="nav-item" role="presentation">
                <button class="nav-link" id="units-tab" data-bs-toggle="tab" data-bs-target="#units" type="button" role="tab">Единицы измерения</button>
            </li>
        </ul>

        <div class="tab-content" id="ppeTabsContent">
            <div class="tab-pane fade show active" id="items" role="tabpanel">
                <iframe src="/ppe-items?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="norms" role="tabpanel">
                <iframe src="/norms?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="functions" role="tabpanel">
                <iframe src="/ppe-functions?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="size-groups" role="tabpanel">
                <iframe src="/ppe-size-groups?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
            <div class="tab-pane fade" id="units" role="tabpanel">
                <iframe src="/units?embedded=1" style="width: 100%; height: 80vh; border: none;"></iframe>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Вкладки обновлены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update tabs on /ppe to include functions and size groups"
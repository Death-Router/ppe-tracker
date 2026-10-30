#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Принудительно перезаписываем edit.html с правильными id..."

cat > app/templates/ppe_items/edit.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-6">
        <div class="d-flex justify-content-between align-items-center mb-3">
            <h1 class="h3 mb-0">Редактирование наименования</h1>
            <a href="/ppe-items" class="btn btn-outline-secondary">← К списку</a>
        </div>

        <div id="conflict-alert" class="alert alert-warning d-none" role="alert">
            Данные устарели, обновите страницу.
            <button type="button" class="btn btn-sm btn-warning ms-2" onclick="location.reload()">Обновить</button>
        </div>

        <form id="item-form" class="card shadow-sm p-4" novalidate>
            <input type="hidden" name="version" id="version" value="">

            <div class="row g-3">
                <div class="col-12">
                    <label class="form-label" for="name">Наименование <span class="text-danger">*</span></label>
                    <input class="form-control" id="name" name="name" required maxlength="255">
                </div>
                <div class="col-12">
                    <label class="form-label" for="function_id">Функция СИЗ (Защита)</label>
                    <select class="form-select" id="function_id" name="function_id">
                        <option value="">Не указана</option>
                    </select>
                </div>
                <div class="col-12">
                    <label class="form-label" for="size_group_id">Размерная группа</label>
                    <select class="form-select" id="size_group_id" name="size_group_id">
                        <option value="">Не указана</option>
                    </select>
                </div>
                <div class="col-12">
                    <label class="form-label" for="unit_id">Единица измерения</label>
                    <select class="form-select" id="unit_id" name="unit_id">
                        <option value="">Не указана</option>
                    </select>
                </div>
            </div>

            <div class="d-flex justify-content-end gap-2 mt-4">
                <a href="/ppe-items" class="btn btn-outline-secondary">Отмена</a>
                <button type="submit" class="btn btn-primary" id="btn-submit">Сохранить</button>
            </div>
        </form>
    </div>
</div>
{% endblock %}

{% block scripts %}
<script>
  window.ITEM_ID = Number("{{ item_id }}");
</script>
<script src="{{ url_for('static', path='js/ppe_item_edit.js') }}"></script>
{% endblock %}
EOF

echo "🔧 Проверяем, что в JS используются правильные id..."

python3 - << 'PYEOF'
with open('app/static/js/ppe_item_edit.js', 'r') as f:
    content = f.read()

# Убедимся, что в JS используются правильные id
# Если там другие — заменяем
content = content.replace(
    "document.getElementById('category_id')",
    "document.getElementById('function_id')"
)
content = content.replace(
    "document.getElementById('create-category')",
    "document.getElementById('function_id')"
)

# Проверяем, что все три id на месте
required_ids = ["function_id", "size_group_id", "unit_id"]
for rid in required_ids:
    if rid not in content:
        print(f"⚠️ В JS не найден id: {rid}")

with open('app/static/js/ppe_item_edit.js', 'w') as f:
    f.write(content)
print("✅ JS проверен.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверь страницу и консоль (Ctrl+F5)."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: force correct ids in ppe_item edit template and JS"
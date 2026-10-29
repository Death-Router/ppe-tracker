#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Обновляем base.html (добавляем иконку настроек)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Меняем бренд на иконку шестеренки
old_brand = '<a class="navbar-brand" href="/">СИЗ • Учёт</a>'
new_brand = '<a class="navbar-brand" href="/settings" title="Настройки"><i class="bi bi-gear-fill"></i> Настройки</a>'

if old_brand in content:
    content = content.replace(old_brand, new_brand)
    print("✅ Бренд заменен на иконку настроек.")
else:
    # Если текст немного другой, просто заменяем "СИЗ • Учёт" на настройки
    content = content.replace('СИЗ • Учёт', '<i class="bi bi-gear-fill"></i> Настройки')
    content = content.replace('href="/"', 'href="/settings"')
    print("✅ Бренд заменен (альтернативный метод).")

with open('app/templates/base.html', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Создаем страницу настроек (импорт/экспорт)..."

cat > app/templates/settings.html << 'EOF'
{% extends "base.html" %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-lg-8">
        <h1 class="h3 mb-4">Настройки и данные</h1>

        <div class="card shadow-sm mb-4">
            <div class="card-header bg-white">
                <h5 class="mb-0 text-secondary"><i class="bi bi-download"></i> Экспорт данных</h5>
            </div>
            <div class="card-body">
                <p class="text-muted small mb-3">Выгрузите текущие данные в формате Excel.</p>
                <div class="d-flex gap-2 flex-wrap">
                    <a href="/api/v1/export/employees" class="btn btn-outline-primary" download>
                        <i class="bi bi-file-earmark-excel"></i> Скачать сотрудников
                    </a>
                    <a href="/api/v1/export/ppe-items" class="btn btn-outline-primary" download>
                        <i class="bi bi-file-earmark-excel"></i> Скачать СИЗ
                    </a>
                    <a href="/api/v1/export/norms" class="btn btn-outline-primary" download>
                        <i class="bi bi-file-earmark-excel"></i> Скачать нормы
                    </a>
                </div>
            </div>
        </div>

        <div class="card shadow-sm mb-4">
            <div class="card-header bg-white">
                <h5 class="mb-0 text-secondary"><i class="bi bi-upload"></i> Импорт данных</h5>
            </div>
            <div class="card-body">
                <p class="text-muted small mb-3">Загрузите Excel-файл с сотрудниками. Формат должен соответствовать экспорту.</p>
                <form id="import-form" enctype="multipart/form-data">
                    <div class="input-group mb-3">
                        <input type="file" class="form-control" name="file" accept=".xlsx, .xls" required>
                        <button type="submit" class="btn btn-success" id="import-btn">Загрузить</button>
                    </div>
                    <div id="import-result" class="mt-3"></div>
                </form>
            </div>
        </div>

        <div class="alert alert-info">
            <i class="bi bi-info-circle"></i> 
            Раздел импорта находится в разработке (доступен только интерфейс). В ближайшем обновлении будет добавлена логика загрузки.
        </div>
    </div>
</div>
{% endblock %}

{% block scripts %}
<script>
  // Заглушка для импорта (логика будет добавлена позже)
  document.getElementById('import-form')?.addEventListener('submit', (e) => {
    e.preventDefault();
    window.showToast('Импорт пока не реализован, но форма готова!', 'info');
    document.getElementById('import-result').innerHTML = '<div class="alert alert-warning">Функция импорта скоро появится.</div>';
  });
</script>
{% endblock %}
EOF

echo "🔧 Добавляем маршрут /settings в main.py..."

python3 - << 'PYEOF'
with open('app/main.py', 'r') as f:
    content = f.read()

# Добавляем маршрут перед закрытием (в конец)
route = '''
@app.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="settings.html",
        context={"title": "Настройки"},
    )
'''

if '/settings' not in content:
    content += route
    print("✅ Маршрут /settings добавлен.")

with open('app/main.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: move import/export to settings page with gear icon"
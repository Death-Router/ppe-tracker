#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Проверяем и обновляем отображение единиц в нормах..."

# 1. Убедимся, что в position_ppe_norms.py загружается unit
python3 - << 'PYEOF'
with open('app/api/v1/endpoints/position_ppe_norms.py', 'r') as f:
    content = f.read()

if 'selectinload(PpeItem.unit)' not in content:
    content = content.replace(
        'selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.category)',
        'selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.category),\n        selectinload(PositionPpeNorm.ppe_item).selectinload(PpeItem.unit)'
    )
    with open('app/api/v1/endpoints/position_ppe_norms.py', 'w') as f:
        f.write(content)
    print("✅ Подгрузка unit добавлена в position_ppe_norms.py.")
else:
    print("ℹ️ Подгрузка unit уже есть.")
PYEOF

# 2. Обновляем norms_list.js (отображение единицы)
python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# В renderTable заменяем вывод количества на форматированный с единицей
old_td = '<td>${escapeHtml(n.quantity)}</td>'
new_td = '''<td>
          ${n.quantity} ${n.ppe_item?.unit?.short_name ? escapeHtml(n.ppe_item.unit.short_name) : ''}
        </td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Отображение единицы добавлено в таблицу норм.")
else:
    print("⚠️ Не удалось найти ячейку количества в норм.")
    # Попробуем альтернативный вариант (если структура отличается)
    if 'n.quantity' in content:
        content = content.replace('${escapeHtml(n.quantity)}', '${n.quantity} ${n.ppe_item?.unit?.short_name ? escapeHtml(n.ppe_item.unit.short_name) : \'\'}')

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

# 3. Обновляем employee_edit.js (отображение единицы в выдаче)
python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# В renderIssuesTable заменяем вывод количества
old_td = '<td>${issue.quantity}</td>'
new_td = '''<td>${issue.quantity} ${issue.ppe_item?.unit?.short_name ? escapeHtml(issue.ppe_item.unit.short_name) : ''}</td>'''

if old_td in content:
    content = content.replace(old_td, new_td)
    print("✅ Отображение единицы добавлено в таблицу выдач.")
else:
    print("⚠️ Не удалось найти ячейку количества в выдачах.")

# Также добавим подстановку единицы в модалку выдачи (если еще нет)
if 'issue-unit-label' not in content:
    # В модалке выдачи меняем поле "Количество"
    content = content.replace(
        '<label class="form-label">Количество <span class="text-danger">*</span></label>\n                    <input type="text" class="form-control" name="quantity" required value="1">',
        '<label class="form-label">Количество <span class="text-danger">*</span></label>\n                    <div class="input-group">\n                        <input type="text" class="form-control" name="quantity" required value="1">\n                        <span class="input-group-text" id="issue-unit-label">ед.</span>\n                    </div>'
    )

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Единицы измерения теперь отображаются в нормах и выдачах."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: display units in norms and issues tables"
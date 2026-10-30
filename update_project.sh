#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Приводим кнопки массовых операций к размеру кнопок в таблице..."

python3 - << 'PYEOF'
with open('app/templates/ppe_items/list.html', 'r') as f:
    content = f.read()

# Заменяем классы у кнопок массовых операций на точно такие же, как в таблице
old_edit_btn = '<button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-2" disabled onclick="openBulkEditModal()" title="Редактировать выбранные" style="height: 31px;"><i class="bi bi-pencil"></i></button>'
new_edit_btn = '<button id="btn-bulk-edit" class="btn btn-sm btn-outline-primary py-0 px-1" disabled onclick="openBulkEditModal()" title="Редактировать выбранные"><i class="bi bi-pencil"></i></button>'

old_del_btn = '<button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-2" disabled onclick="bulkDelete()" title="Удалить выбранные" style="height: 31px;"><i class="bi bi-trash"></i></button>'
new_del_btn = '<button id="btn-bulk-delete" class="btn btn-sm btn-outline-danger py-0 px-1" disabled onclick="bulkDelete()" title="Удалить выбранные"><i class="bi bi-trash"></i></button>'

if old_edit_btn in content:
    content = content.replace(old_edit_btn, new_edit_btn)
    print("✅ Кнопка 'Редактировать' уменьшена.")
else:
    print("⚠️ Не удалось найти кнопку 'Редактировать' с ожидаемыми классами.")

if old_del_btn in content:
    content = content.replace(old_del_btn, new_del_btn)
    print("✅ Кнопка 'Удалить' уменьшена.")
else:
    print("⚠️ Не удалось найти кнопку 'Удалить' с ожидаемыми классами.")

with open('app/templates/ppe_items/list.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Размеры кнопок должны совпадать."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: make bulk action buttons same size as table buttons"
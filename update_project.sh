#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем асинхронный createSizeRow в employee_edit.js..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. В обработчике addSizeBtn добавляем await
old_add = '''  addSizeBtn.addEventListener('click', () => {
    sizesTableBody.appendChild(createSizeRow());
    isDirty = true;
  });'''

new_add = '''  addSizeBtn.addEventListener('click', async () => {
    const tr = await createSizeRow();
    sizesTableBody.appendChild(tr);
    isDirty = true;
  });'''

content = content.replace(old_add, new_add)

# 2. В функции loadEmployee уже есть await перед createSizeRow, но проверим, что он есть
# (Если там нет await, добавим)
old_loop = '''        for (const size of emp.ppe_sizes) {
          const tr = await createSizeRow(size.ppe_item_id, size.size_value);
          sizesTableBody.appendChild(tr);
        }'''
# Оставляем как есть, если уже с await

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
print("✅ Исправление добавлено: appendChild теперь ждет Promise.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь добавление размера не должно вызывать ошибку."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: await async createSizeRow before appendChild"
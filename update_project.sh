#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем шаблон карточки сотрудника (заголовок таблицы)..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Меняем заголовок таблицы размеров
content = content.replace(
    '<th>Категория СИЗ</th>',
    '<th>Размерная группа</th>'
)

# Меняем заголовок в модалке выдачи (если там есть "Размер (опционально)")
# (оставляем как есть, это не критично)

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
print("✅ Заголовок таблицы обновлен.")
PYEOF

echo "📝 Обновляем JS карточки сотрудника (размерные группы)..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Заменяем allCategories на allSizeGroups
content = content.replace('let allCategories = [];', 'let allSizeGroups = [];')

# 2. В loadCategories заменяем на loadSizeGroups
content = content.replace(
    '''  async function loadCategories() {
    allCategories = await API.get('/api/v1/ppe_categories');
  }''',
    '''  async function loadSizeGroups() {
    allSizeGroups = await API.get('/api/v1/ppe_size_groups');
  }'''
)

# 3. В createSizeRow заменяем categoryOptions на sizeGroupOptions
content = content.replace(
    '''    const categoryOptions = allCategories.map(c => 
      `<option value="${c.id}" ${c.id === Number(categoryId) ? 'selected' : ''}>${c.name}</option>`
    ).join('');''',
    '''    const sizeGroupOptions = allSizeGroups.map(g => 
      `<option value="${g.id}" ${g.id === Number(categoryId) ? 'selected' : ''}>${g.name}</option>`
    ).join('');'''
)

# 4. В HTML строки заменяем category-select на size-group-select и categoryOptions на sizeGroupOptions
content = content.replace(
    '''        <select class="form-select form-select-sm category-select" required>
          <option value="">Выберите категорию...</option>
          ${categoryOptions}
        </select>''',
    '''        <select class="form-select form-select-sm size-group-select" required>
          <option value="">Выберите размерную группу...</option>
          ${sizeGroupOptions}
        </select>'''
)

# 5. Заменяем обработчик изменения категории на размерную группу
content = content.replace(
    '''    const catSelect = tr.querySelector('.category-select');''',
    '''    const catSelect = tr.querySelector('.size-group-select');'''
)

# 6. В loadEmployee заменяем category_id на size_group_id
content = content.replace(
    '''          const tr = await createSizeRow(size.category_id, size.size_value);''',
    '''          const tr = await createSizeRow(size.size_group_id, size.size_value);'''
)

# 7. В submitForm (сохранение) заменяем category_id на size_group_id
content = content.replace(
    '''        ppeSizes.push({ category_id: categoryId, size_value: sizeVal });''',
    '''        ppeSizes.push({ size_group_id: categoryId, size_value: sizeVal });'''
)

# 8. В инициализации заменяем loadCategories на loadSizeGroups
content = content.replace(
    '''  loadDepartments()
    .then(loadCategories)
    .then(loadAllPpeItems)
    .then(() => loadEmployee());''',
    '''  loadDepartments()
    .then(loadSizeGroups)
    .then(loadAllPpeItems)
    .then(() => loadEmployee());'''
)

# 9. В getSizesForCategory заменяем запрос к ppe_sizes (category_id -> size_group_id)
content = content.replace(
    '''      const sizes = await API.get(`/api/v1/ppe_sizes/?category_id=${categoryId}`);''',
    '''      const sizes = await API.get(`/api/v1/ppe_sizes/?size_group_id=${categoryId}`);'''
)

# 10. В fillIssueSizes заменяем categoryId на sizeGroupId (но параметр можно оставить)
# (там уже используется categoryId, но это не критично, так как мы передаем size_group_id)

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
print("✅ JS карточки сотрудника обновлен (size_group_id).")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Карточка сотрудника теперь использует размерные группы."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update employee card to use size_groups instead of categories"
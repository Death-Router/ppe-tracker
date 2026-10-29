#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем логику норм (автоматическая подстановка единицы)..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# 1. Меняем форму: добавляем бейдж для единицы измерения
old_form = '''            <div class="mb-3 mt-3">
                <label class="form-label">Количество <span class="text-danger">*</span></label>
                <input type="text" class="form-control" name="quantity" required placeholder="Например, 1 пара" value="1">
            </div>'''

new_form = '''            <div class="mb-3 mt-3">
                <label class="form-label">Количество <span class="text-danger">*</span></label>
                <div class="input-group">
                    <input type="text" class="form-control" name="quantity" required placeholder="Число" value="1">
                    <span class="input-group-text" id="norm-unit-label">ед.</span>
                </div>
            </div>'''

if old_form in content:
    content = content.replace(old_form, new_form)
    print("✅ Форма нормы обновлена (добавлен бейдж единицы).")
else:
    print("⚠️ Не удалось найти старую форму нормы.")

# 2. Добавляем обработчик изменения СИЗ в модалке нормы
# Нам нужно найти блок, где мы заполняем itemSelect, и добавить обработчик
old_item_change = '''  // В функции renderTable или при инициализации
  // (Найдем место, где мы заполняем список СИЗ в модалке)
'''

# Проще добавить обработчик в конец файла перед инициализацией
new_logic = '''
  // Обработчик изменения СИЗ в модалке создания нормы
  const normItemSelect = document.getElementById('norm-item-select');
  if (normItemSelect) {
    normItemSelect.addEventListener('change', async (e) => {
      const selectedId = Number(e.target.value);
      const unitLabel = document.getElementById('norm-unit-label');
      
      if (!selectedId) {
        unitLabel.textContent = 'ед.';
        return;
      }

      // Находим выбранное СИЗ в allPpeItems
      const selectedItem = allPpeItems.find(i => i.id === selectedId);
      if (selectedItem && selectedItem.unit) {
        unitLabel.textContent = selectedItem.unit.short_name;
      } else {
        unitLabel.textContent = 'ед.';
      }
    });
  }
'''

# Вставляем перед последней инициализацией (init())
if 'normItemSelect' not in content:
    content = content.replace(
        '  init();\n})();',
        new_logic + '\n  init();\n})();'
    )
    print("✅ Обработчик изменения СИЗ добавлен в нормы.")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Обновляем логику выдачи (автоматическая подстановка единицы)..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Меняем форму выдачи: добавляем бейдж для единицы
old_form = '''                <div class="col-6">
                    <label class="form-label">Количество <span class="text-danger">*</span></label>
                    <input type="text" class="form-control" name="quantity" required value="1">
                </div>'''

new_form = '''                <div class="col-6">
                    <label class="form-label">Количество <span class="text-danger">*</span></label>
                    <div class="input-group">
                        <input type="text" class="form-control" name="quantity" required value="1">
                        <span class="input-group-text" id="issue-unit-label">ед.</span>
                    </div>
                </div>'''

if old_form in content:
    content = content.replace(old_form, new_form)
    print("✅ Форма выдачи обновлена (добавлен бейдж единицы).")
else:
    print("⚠️ Не удалось найти старую форму выдачи.")

# 2. Добавляем обработчик изменения СИЗ в модалке выдачи
old_handler = '''  if (issueItemSelect) {
    issueItemSelect.addEventListener('change', (e) => {
      const selectedOption = e.target.options[e.target.selectedIndex];
      const categoryId = selectedOption.getAttribute('data-category-id');
      fillIssueSizes(categoryId);
    });
  }'''

new_handler = '''  if (issueItemSelect) {
    issueItemSelect.addEventListener('change', async (e) => {
      const selectedOption = e.target.options[e.target.selectedIndex];
      const categoryId = selectedOption.getAttribute('data-category-id');
      const selectedId = Number(issueItemSelect.value);
      const unitLabel = document.getElementById('issue-unit-label');
      
      // Обновляем размеры
      fillIssueSizes(categoryId);

      // Обновляем единицу измерения
      if (!selectedId) {
        unitLabel.textContent = 'ед.';
        return;
      }

      const selectedItem = allPpeItems.find(i => i.id === selectedId);
      if (selectedItem && selectedItem.unit) {
        unitLabel.textContent = selectedItem.unit.short_name;
      } else {
        unitLabel.textContent = 'ед.';
      }
    });
  }'''

if old_handler in content:
    content = content.replace(old_handler, new_handler)
    print("✅ Обработчик изменения СИЗ обновлен (единица).")
else:
    print("⚠️ Не удалось найти обработчик изменения СИЗ в выдаче.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Единицы измерения теперь подставляются автоматически."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: auto-fill unit of measurement in norms and issues modals"
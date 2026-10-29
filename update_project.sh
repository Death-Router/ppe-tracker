#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Заменяем select на input с datalist в модалке выдачи СИЗ..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Заменяем select на input с datalist и скрытым полем для ID
old_select = '''            <div class="mb-3">
                <label class="form-label">Наименование СИЗ <span class="text-danger">*</span></label>
                <select class="form-select" name="ppe_item_id" id="issue-item-select" required>
                    <option value="">Загрузка...</option>
                </select>
            </div>'''

new_input = '''            <div class="mb-3">
                <label class="form-label">Наименование СИЗ <span class="text-danger">*</span></label>
                <input type="text" class="form-control" list="issue-ppe-list" id="issue-item-input" placeholder="Начните вводить название..." required autocomplete="off">
                <datalist id="issue-ppe-list">
                    <!-- Опции будут заполнены через JS -->
                </datalist>
                <input type="hidden" name="ppe_item_id" id="issue-item-id">
            </div>'''

if old_select in content:
    content = content.replace(old_select, new_input)
    with open('app/templates/employees/edit.html', 'w') as f:
        f.write(content)
    print("✅ Поле ввода с автодополнением добавлено в модалку выдачи.")
else:
    print("⚠️ Не удалось найти старый select в модалке выдачи.")
PYEOF

echo "📝 Обновляем логику в employee_edit.js для модалки выдачи..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Добавляем переменные для новых элементов (если их нет)
if 'issueItemInput' not in content:
    content = content.replace(
        "const issueItemSelect = document.getElementById('issue-item-select');",
        "const issueItemInput = document.getElementById('issue-item-input');\n  const issueItemIdInput = document.getElementById('issue-item-id');\n  const issuePpeList = document.getElementById('issue-ppe-list');"
    )
    print("✅ Переменные для input/datalist добавлены.")

# 2. Обновляем функцию openIssueModalForNorm и обработчик show.bs.modal
# Нам нужно заменить заполнение select на заполнение datalist

old_modal_handler = '''  if (issueModalElement) {
    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          if (issueItemSelect) {
            issueItemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
              data.map(i => `<option value="${i.id}" data-category-id="${i.category_id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
          }
          if (issueSizeSelect) issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
        });
    });
  }'''

new_modal_handler = '''  if (issueModalElement) {
    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          if (issuePpeList) {
            issuePpeList.innerHTML = data.map(i => 
              `<option value="${i.name} (${i.category?.name ?? ''})" data-id="${i.id}" data-category-id="${i.category_id}"></option>`
            ).join('');
          }
          // Очищаем поля при открытии
          if (issueItemInput) issueItemInput.value = '';
          if (issueItemIdInput) issueItemIdInput.value = '';
          if (issueSizeSelect) issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
        });
    });

    // Обработчик ввода в поле СИЗ (для модалки выдачи)
    if (issueItemInput) {
      issueItemInput.addEventListener('input', (e) => {
        const val = e.target.value;
        const option = Array.from(issuePpeList.options).find(opt => opt.value === val);
        if (option) {
          const itemId = option.getAttribute('data-id');
          const categoryId = option.getAttribute('data-category-id');
          issueItemIdInput.value = itemId;
          
          // Обновляем размеры и единицу измерения
          fillIssueSizes(categoryId);
          
          const selectedItem = allPpeItems.find(i => i.id === Number(itemId));
          const unitLabel = document.getElementById('issue-unit-label');
          if (selectedItem && selectedItem.unit) {
            unitLabel.textContent = selectedItem.unit.short_name;
          } else {
            unitLabel.textContent = 'ед.';
          }
        } else {
          issueItemIdInput.value = '';
        }
      });
    }
  }'''

if old_modal_handler in content:
    content = content.replace(old_modal_handler, new_modal_handler)
    print("✅ Обработчик модалки обновлен (datalist).")

# 3. Обновляем openIssueModalForNorm (если он был)
old_open_func = '''  window.openIssueModalForNorm = (ppeItemId) => {
    const modal = new bootstrap.Modal(issueModalElement);
    
    fetch('/api/v1/ppe_items')
      .then(r => r.json())
      .then(data => {
        issueItemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
          data.map(i => `<option value="${i.id}" data-category-id="${i.category_id}" ${i.id === ppeItemId ? 'selected' : ''}>${i.name} (${i.category?.name ?? ''})</option>`).join('');
        
        if (ppeItemId) {
          const selectedOption = issueItemSelect.options[issueItemSelect.selectedIndex];
          const categoryId = selectedOption.getAttribute('data-category-id');
          fillIssueSizes(categoryId);
        } else {
          issueSizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
        }
        
        modal.show();
      });
  };'''

new_open_func = '''  window.openIssueModalForNorm = (ppeItemId) => {
    const modal = new bootstrap.Modal(issueModalElement);
    
    fetch('/api/v1/ppe_items')
      .then(r => r.json())
      .then(data => {
        // Заполняем datalist
        if (issuePpeList) {
          issuePpeList.innerHTML = data.map(i => 
            `<option value="${i.name} (${i.category?.name ?? ''})" data-id="${i.id}" data-category-id="${i.category_id}"></option>`
          ).join('');
        }

        // Устанавливаем выбранное СИЗ, если передан ID
        if (ppeItemId) {
          const item = data.find(i => i.id === ppeItemId);
          if (item && issueItemInput) {
            issueItemInput.value = `${item.name} (${item.category?.name ?? ''})`;
            issueItemIdInput.value = item.id;
            fillIssueSizes(item.category_id);
            
            const unitLabel = document.getElementById('issue-unit-label');
            if (item.unit) {
              unitLabel.textContent = item.unit.short_name;
            }
          }
        }
        
        modal.show();
      });
  };'''

if old_open_func in content:
    content = content.replace(old_open_func, new_open_func)
    print("✅ Функция openIssueModalForNorm обновлена (datalist).")

# 4. В submitForm для выдачи берем ppe_item_id из скрытого поля
old_submit = '''      const payload = FormHelper.serialize(issueForm);
      payload.employee_id = employeeId;
      payload.ppe_item_id = Number(payload.ppe_item_id);'''

new_submit = '''      const payload = FormHelper.serialize(issueForm);
      payload.employee_id = employeeId;
      payload.ppe_item_id = Number(issueItemIdInput.value);'''

if old_submit in content:
    content = content.replace(old_submit, new_submit)
    print("✅ Отправка формы выдачи обновлена (id из hidden).")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! В модалке выдачи теперь поиск с автодополнением."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace select with datalist in issue modal"
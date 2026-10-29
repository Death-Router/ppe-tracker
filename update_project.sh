#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем поле размера в модалке выдачи..."

python3 - << 'PYEOF'
import re

# 1. Обновляем HTML модалки
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Ищем input для размера внутри issueModal
# Паттерн: <input ... name="size_value" ...>
pattern = r'(<label class="form-label">Размер \(опционально\)</label>\s*)(<input[^>]*name="size_value"[^>]*>)'
match = re.search(pattern, content, re.DOTALL)

if match:
    # Заменяем input на select
    new_select = '<select class="form-select" name="size_value" id="issue-size-select"><option value="">Сначала выберите СИЗ...</option></select>'
    content = content.replace(match.group(0), match.group(1) + new_select)
    print("✅ HTML: input заменен на select.")
else:
    # Если паттерн не сработал, просто ищем input
    old_input = '<input type="text" class="form-control" name="size_value" placeholder="Например, 42">'
    if old_input in content:
        content = content.replace(old_input, '<select class="form-select" name="size_value" id="issue-size-select"><option value="">Сначала выберите СИЗ...</option></select>')
        print("✅ HTML: input заменен на select (прямой поиск).")
    else:
        print("⚠️ HTML: не удалось найти input для размера.")

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Обновляем JS (динамическое заполнение размеров в модалке)..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Проверяем, есть ли уже логика для issue-size-select
if 'issue-size-select' not in content:
    # Добавляем обработчик для issue-item-select, который заполняет issue-size-select
    # Находим блок, где мы заполняем issue-item-select
    old_code = '''    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          const select = document.getElementById('issue-item-select');
          if (select) {
            select.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
              data.map(i => `<option value="${i.id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
          }
        })
        .catch(err => console.error('Ошибка загрузки СИЗ:', err));
    });'''

    new_code = '''    issueModalElement.addEventListener('show.bs.modal', () => {
      fetch('/api/v1/ppe_items')
        .then(r => r.json())
        .then(data => {
          const select = document.getElementById('issue-item-select');
          if (select) {
            select.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
              data.map(i => `<option value="${i.id}" data-category-id="${i.category_id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');
          }
          // Очищаем select размера при открытии
          const sizeSelect = document.getElementById('issue-size-select');
          if (sizeSelect) {
            sizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
          }
        })
        .catch(err => console.error('Ошибка загрузки СИЗ:', err));
    });

    // Обработчик изменения СИЗ в модалке
    const issueItemSelect = document.getElementById('issue-item-select');
    if (issueItemSelect) {
      issueItemSelect.addEventListener('change', async (e) => {
        const selectedOption = e.target.options[e.target.selectedIndex];
        const categoryId = selectedOption.getAttribute('data-category-id');
        const sizeSelect = document.getElementById('issue-size-select');
        
        if (!categoryId) {
          if (sizeSelect) sizeSelect.innerHTML = '<option value="">Сначала выберите СИЗ...</option>';
          return;
        }

        try {
          const sizes = await getSizesForCategory(categoryId);
          const empGender = form.elements['gender'].value || null;
          let filteredSizes = sizes;
          if (empGender) {
            filteredSizes = sizes.filter(s => !s.gender || s.gender === empGender);
          }

          if (sizeSelect) {
            if (filteredSizes.length > 0) {
              sizeSelect.innerHTML = '<option value="">Выберите размер...</option>' + 
                filteredSizes.map(s => {
                  const genderLabel = s.gender === 'М' ? ' (М)' : s.gender === 'Ж' ? ' (Ж)' : '';
                  return `<option value="${s.size_value}">${s.size_value}${genderLabel}</option>`;
                }).join('');
            } else {
              // Если размеров нет, делаем поле снова текстовым (или оставляем пустым)
              sizeSelect.innerHTML = '<option value="">Нет размеров</option>';
            }
          }
        } catch (err) {
          console.error('Ошибка загрузки размеров:', err);
          if (sizeSelect) sizeSelect.innerHTML = '<option value="">Ошибка</option>';
        }
      });
    }'''

    if old_code in content:
        content = content.replace(old_code, new_code)
        print("✅ JS: обработчик для размера в модалке добавлен.")
    else:
        print("⚠️ JS: не удалось найти блок issueModalElement. Проверь файл вручную.")
else:
    print("ℹ️ JS: логика для issue-size-select уже есть.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Размер в модалке выдачи должен стать выпадающим списком."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: use size dictionary in issue modal (force)"
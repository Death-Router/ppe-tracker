#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем шаблон карточки (добавляем ID заголовку)..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# Заменяем заголовок на элемент с id="employee-title"
old_title = '<h1 class="h3 mb-0">Редактирование сотрудника</h1>'
new_title = '<h1 class="h3 mb-0" id="employee-title">Редактирование сотрудника</h1>'

if old_title in content:
    content = content.replace(old_title, new_title)
    with open('app/templates/employees/edit.html', 'w') as f:
        f.write(content)
    print("✅ Заголовку добавлен id.")
else:
    print("⚠️ Не удалось найти заголовок в edit.html.")
PYEOF

echo "📝 Обновляем JS (меняем заголовок на ФИО)..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# В функции loadEmployee после заполнения полей добавляем смену заголовка
old_code = '''      versionInput.value = emp.version ?? '';
      isDirty = false;
      
      // Загружаем выдачи и нормы'''

new_code = '''      versionInput.value = emp.version ?? '';
      isDirty = false;

      // Меняем заголовок на ФИО сотрудника
      const titleEl = document.getElementById('employee-title');
      if (titleEl) {
        const fio = [emp.last_name, emp.first_name, emp.middle_name].filter(Boolean).join(' ');
        titleEl.textContent = `Редактирование: ${fio}`;
      }
      
      // Загружаем выдачи и нормы'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Логика смены заголовка добавлена.")
else:
    print("⚠️ Не удалось найти блок загрузки сотрудника для вставки логики.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь в заголовке отображается ФИО сотрудника."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: display employee full name in card header"
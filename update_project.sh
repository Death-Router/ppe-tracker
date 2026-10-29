#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем кнопку 'Выдать' в модалке (убираем submit)..."

python3 - << 'PYEOF'
with open('app/templates/employees/edit.html', 'r') as f:
    content = f.read()

# 1. Меняем тип кнопки в модалке выдачи на "button" и добавляем onclick
old_button = '<button type="submit" class="btn btn-primary">Выдать</button>'
new_button = '<button type="button" class="btn btn-primary" onclick="submitIssueForm(event)">Выдать</button>'

if old_button in content:
    content = content.replace(old_button, new_button)
    print("✅ Кнопка 'Выдать' изменена на type='button' с onclick.")
else:
    print("⚠️ Не удалось найти кнопку 'Выдать' в edit.html.")

# 2. На всякий случай, если форма выдачи всё ещё внутри основной формы, 
# убедимся, что у неё нет атрибута action (чтобы она не отправлялась)
# Но мы уже вынесли её, так что это не должно быть проблемой.

with open('app/templates/employees/edit.html', 'w') as f:
    f.write(content)
PYEOF

echo "📝 Добавляем функцию submitIssueForm в employee_edit.js..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# Проверяем, есть ли уже функция submitIssueForm
if 'function submitIssueForm' not in content:
    # Добавляем функцию в конец файла (перед последней закрывающей скобкой)
    # Находим последнюю скобку
    last_brace = content.rfind('})();')
    if last_brace != -1:
        new_func = '''
  // Функция для отправки формы выдачи (вызывается по кнопке)
  window.submitIssueForm = async (event) => {
    if (event) event.preventDefault();
    
    const form = document.getElementById('issue-form');
    if (!form) return;

    const payload = FormHelper.serialize(form);
    payload.employee_id = employeeId;
    // Берем ID СИЗ из скрытого поля (мы его синхронизировали)
    payload.ppe_item_id = Number(issueItemIdInput.value);
    
    if (!payload.ppe_item_id) {
      window.showToast('Выберите СИЗ из списка', 'danger');
      return;
    }

    if (!payload.issue_date) payload.issue_date = new Date().toISOString().split('T')[0];
    if (payload.size_value === '') payload.size_value = null;

    const btn = document.querySelector('button[onclick="submitIssueForm(event)"]');
    if (btn) btn.disabled = true;

    try {
      await API.post('/api/v1/employee_ppe_issues/', payload);
      window.showToast('СИЗ выдано', 'success');
      bootstrap.Modal.getInstance(document.getElementById('issueModal')).hide();
      form.reset();
      // Сбрасываем скрытые поля
      issueItemIdInput.value = '';
      issueItemInput.value = '';
      await loadIssues();
    } catch (err) {
      window.showToast(`Ошибка: ${err.message}`, 'danger');
    } finally {
      if (btn) btn.disabled = false;
    }
  };
'''
        content = content[:last_brace] + new_func + '\n' + content[last_brace:]
        print("✅ Функция submitIssueForm добавлена в конец файла.")
    else:
        print("⚠️ Не удалось найти конец файла для вставки функции.")
else:
    print("ℹ️ Функция submitIssueForm уже есть.")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопка 'Выдать' теперь не вызывает перезагрузку."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: prevent form submit on issue button (use type=button + onclick)"
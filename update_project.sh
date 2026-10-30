#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем сброс валидации при смене подразделения..."

python3 - << 'PYEOF'
with open('app/static/js/employee_edit.js', 'r') as f:
    content = f.read()

# 1. Находим обработчик изменения подразделения
old_handler = '''  deptSelect.addEventListener('change', (e) => {
    loadPositions(e.target.value);
  });'''

new_handler = '''  deptSelect.addEventListener('change', async (e) => {
    await loadPositions(e.target.value);
    // Принудительно обновляем валидацию после загрузки должностей
    const form = document.getElementById('employee-form');
    if (form) {
      const btn = form.querySelector('button[type="submit"]');
      if (btn) btn.disabled = !form.checkValidity();
    }
  });'''

if old_handler in content:
    content = content.replace(old_handler, new_handler)
    print("✅ Обработчик смены подразделения обновлен.")
else:
    print("⚠️ Не удалось найти обработчик смены подразделения.")
    # Попробуем найти другой вариант
    old_handler2 = '''  deptSelect.addEventListener('change', (e) => loadPositions(e.target.value));'''
    if old_handler2 in content:
        content = content.replace(old_handler2, new_handler)
        print("✅ Обработчик смены подразделения обновлен (альтернативный вариант).")

with open('app/static/js/employee_edit.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Валидация должна обновляться при смене подразделения."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: update validation when department changes (position reset)"
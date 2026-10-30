#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Убираем MutationObserver из скрипта валидации (чтобы не было зависания)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Находим старый скрипт валидации и заменяем его на безопасный
old_script = '''<script>
  document.addEventListener('DOMContentLoaded', () => {
    // Находим все формы на странице
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
      // Ищем кнопку submit внутри формы (или связанную)
      const submitBtn = form.querySelector('button[type="submit"]');
      if (!submitBtn) return;
      
      // Функция проверки валидности
      const checkValidity = () => {
        if (form.checkValidity()) {
          submitBtn.disabled = false;
        } else {
          submitBtn.disabled = true;
        }
      };
      
      // Проверяем при загрузке и при любом изменении
      checkValidity();
      form.addEventListener('input', checkValidity);
      form.addEventListener('change', checkValidity);
      
      // Также проверяем, если поля обновляются программно (например, из модалки)
      const observer = new MutationObserver(checkValidity);
      observer.observe(form, { attributes: true, childList: true, subtree: true });
    });
  });
</script>'''

new_script = '''<script>
  document.addEventListener('DOMContentLoaded', () => {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
      const submitBtn = form.querySelector('button[type="submit"]');
      if (!submitBtn) return;
      
      const checkValidity = () => {
        submitBtn.disabled = !form.checkValidity();
      };
      
      checkValidity();
      form.addEventListener('input', checkValidity);
      form.addEventListener('change', checkValidity);
    });
  });
</script>'''

if old_script in content:
    content = content.replace(old_script, new_script)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Скрипт валидации упрощен (без MutationObserver).")
else:
    print("⚠️ Не удалось найти старый скрипт валидации.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Страница /login должна перестать зависать."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove MutationObserver to prevent page freeze"
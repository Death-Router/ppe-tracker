#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем валидацию для динамических модалок..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Скрипт, который будет следить за появлением модалок и валидировать их формы
validation_script = '''
<script>
  document.addEventListener('DOMContentLoaded', () => {
    // Функция для настройки валидации на форме
    function setupFormValidation(form) {
      const submitBtn = form.querySelector('button[type="submit"]');
      if (!submitBtn) return;
      
      const checkValidity = () => {
        submitBtn.disabled = !form.checkValidity();
      };
      
      checkValidity();
      form.addEventListener('input', checkValidity);
      form.addEventListener('change', checkValidity);
    }
    
    // Настраиваем валидацию для всех существующих форм
    document.querySelectorAll('form').forEach(setupFormValidation);
    
    // Следим за появлением новых форм в модалках
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1) {
            // Если добавлен элемент form
            if (node.tagName === 'FORM') {
              setupFormValidation(node);
            }
            // Если добавлены элементы внутри формы
            if (node.querySelectorAll) {
              node.querySelectorAll('form').forEach(setupFormValidation);
            }
          }
        });
      });
    });
    
    // Наблюдаем за всем документом
    observer.observe(document.body, { childList: true, subtree: true });
  });
</script>
'''

# Вставляем скрипт перед закрывающим тегом body, если его там нет
if 'setupFormValidation' not in content:
    content = content.replace('</body>', validation_script + '\n</body>')
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Скрипт валидации для динамических форм добавлен.")
else:
    print("ℹ️ Скрипт валидации уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Валидация должна работать и в модалках."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: add validation for dynamically loaded forms (modals)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем глобальную валидацию форм (блокировка кнопки)..."
echo "Добавляем скрипт в base.html..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Скрипт, который будет следить за формами и блокировать кнопки
validation_script = '''
<script>
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
</script>
'''

if 'checkValidity' not in content:
    content = content.replace('</body>', validation_script + '\n</body>')
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Глобальный скрипт валидации добавлен в base.html.")
else:
    print("ℹ️ Скрипт валидации уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Кнопки 'Сохранить'/'Применить' будут блокироваться, пока не заполнены обязательные поля."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add global form validation (disable submit until required fields filled)"
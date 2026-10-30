#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Включаем проверку орфографии для текстовых полей (кроме ФИО)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

script = '''
<script>
  document.addEventListener('DOMContentLoaded', () => {
    // Поля, для которых проверка орфографии НЕ нужна (ФИО, номера, коды, названия)
    const noSpellcheckNames = [
      'last_name', 'first_name', 'middle_name', // ФИО
      'personnel_number', // Табельный номер
      'name', // Названия (СИЗ, категории, группы, единицы, подразделения, должности)
      'short_name', // Сокращения
      'category_id', 'department_id', 'position_id', 'function_id', 'size_group_id', 'unit_id', 'ppe_item_id', // ID
      'version', 'login', 'username', 'password', 'role' // Служебные
    ];

    // Включаем проверку для всех textarea и text-инпутов
    document.querySelectorAll('textarea, input[type="text"], input[type="search"]').forEach(el => {
      const name = el.getAttribute('name');
      if (name && noSpellcheckNames.includes(name)) {
        el.setAttribute('spellcheck', 'false');
      } else {
        el.setAttribute('spellcheck', 'true');
      }
    });
  });
</script>
'''

if 'noSpellcheckNames' not in content:
    content = content.replace('</body>', script + '\n</body>')
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Скрипт проверки орфографии добавлен в base.html.")
else:
    print("ℹ️ Скрипт уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверка орфографии настроена."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: enable spellcheck for text fields (except names, numbers, codes)"
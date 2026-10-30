#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Делаем маску ввода для полей ФИО (жёсткая фильтрация)..."

# 1. Полностью заменяем validators.js — добавляем маску
cat > app/static/js/common/validators.js << 'EOF'
// app/static/js/common/validators.js
window.Validators = {
  // Разрешённые символы для ФИО: русские буквы и дефис
  nameAllowedChars: /[^А-Яа-яЁё-]/g,

  // Итоговый формат (для бэкенда / финальной проверки)
  // "Иванов", "Петрова-Водкина"
  nameFormat: /^[А-ЯЁ][а-яё]+(?:-[А-ЯЁ][а-яё]+)*$/,

  MAX_NAME_LEN: 32,

  // Применяет маску к input: фильтрует символы и управляет регистром
  applyNameMask(input) {
    if (!input) return;

    const format = (raw) => {
      // 1. Убираем всё, кроме русских букв и дефиса
      let s = String(raw).replace(this.nameAllowedChars, '');

      // 2. Разбиваем по дефису и приводим каждую часть к формату
      //    "иванов-петров" -> "Иванов-Петров"
      s = s.split('-').map(part => {
        if (!part) return '';
        // Первая буква — заглавная, остальные — строчные
        return part.charAt(0).toUpperCase() + part.slice(1).toLowerCase();
      }).join('-');

      // 3. Обрезаем до MAX
      if (s.length > this.MAX_NAME_LEN) s = s.slice(0, this.MAX_NAME_LEN);

      // 4. Не даём начинать с дефиса и не допускаем двойных дефисов
      s = s.replace(/^-+/, '').replace(/--+/g, '-');

      return s;
    };

    const handler = () => {
      const before = input.value;
      const after = format(before);
      if (before !== after) {
        // Сохраняем позицию курсора максимально близко
        const pos = input.selectionStart ?? after.length;
        input.value = after;
        const shift = after.length - before.length;
        const newPos = Math.max(0, Math.min(after.length, pos + shift));
        try { input.setSelectionRange(newPos, newPos); } catch { /* ignore */ }
      }

      // Валидность: >= 2 символов и соответствует финальному формату
      const isValid = after.length >= 2 && this.nameFormat.test(after);
      input.classList.toggle('is-valid', isValid);
      input.classList.toggle('is-invalid', after.length > 0 && !isValid);
      input.setCustomValidity(isValid ? '' : (after.length < 2 ? 'Слишком короткое значение' : 'Недопустимый формат ФИО'));
    };

    // 'input' ловит и ввод с клавиатуры, и вставку из буфера
    input.addEventListener('input', handler);
    // На случай автозаполнения/программной установки
    input.addEventListener('change', handler);
    // Первый прогон — на случай, если значение уже было
    handler();
  },
};
EOF

echo "✅ validators.js обновлён (маска ФИО)."

# 2. Пробрасываем маску ко всем полям ФИО на страницах
#    (переиспользуем существующий хук attachNameValidation из form.js,
#     но теперь он будет не «валидировать», а «применять маску»)
python3 - << 'PYEOF'
# Заменяем содержимое функции attachNameValidation в common/form.js
with open('app/static/js/common/form.js', 'r') as f:
    content = f.read()

# Убираем старую реализацию (между комментарием и концом функции)
import re
content = re.sub(
    r'// --- Живая валидация ФИО ---.*?(?=\n// ---|\Z)',
    '',
    content,
    flags=re.DOTALL,
)

# Добавляем новую — с маской
content += '''
// --- Живая маска для полей ФИО ---
window.attachNameValidation = function (form, fieldNames) {
  if (!form || !window.Validators) return;
  fieldNames.forEach(name => {
    const el = form.elements[name];
    if (el) Validators.applyNameMask(el);
  });
};
'''

with open('app/static/js/common/form.js', 'w') as f:
    f.write(content)
print("✅ attachNameValidation переведён на маску.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Маска ФИО работает на лету."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: input mask for FIO fields (russian letters, auto-case, dash support)"
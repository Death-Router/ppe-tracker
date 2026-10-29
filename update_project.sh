#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📐 Выравниваем поля в модалке создания сотрудника..."

python3 - << 'PYEOF'
with open('app/templates/employees/list.html', 'r') as f:
    content = f.read()

# Ищем блок с полями в модалке создания (от <div class="row g-3"> до </div> перед modal-footer)
# Заменяем его на аккуратную сетку
import re

# Паттерн для поиска блока полей в модалке создания
# Начинается с <div class="row g-3"> и заканчивается перед </div> (закрытие модалки)
# Мы заменим всё содержимое этого блока

old_block_pattern = r'(<div class="modal-body">\s*)(<div class="row g-3">.*?)(\s*</div>\s*<div class="modal-footer">)'
match = re.search(old_block_pattern, content, re.DOTALL)

if match:
    new_fields = '''
            <div class="row g-3">
                <div class="col-md-4">
                    <label class="form-label">Фамилия <span class="text-danger">*</span></label>
                    <input class="form-control" name="last_name" required maxlength="100">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Имя <span class="text-danger">*</span></label>
                    <input class="form-control" name="first_name" required maxlength="100">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Отчество <span class="text-danger">*</span></label>
                    <input class="form-control" name="middle_name" required maxlength="100">
                </div>

                <div class="col-md-4">
                    <label class="form-label">Табельный номер <span class="text-danger">*</span></label>
                    <input class="form-control" name="personnel_number" required maxlength="20">
                </div>
                <div class="col-md-4">
                    <label class="form-label">Подразделение <span class="text-danger">*</span></label>
                    <select class="form-select" name="department_id" id="create-dept" required>
                        <option value="">Выберите подразделение...</option>
                    </select>
                </div>
                <div class="col-md-4">
                    <label class="form-label">Должность <span class="text-danger">*</span></label>
                    <select class="form-select" name="position_id" id="create-pos" required>
                        <option value="">Сначала выберите подразделение</option>
                    </select>
                </div>

                <div class="col-md-3">
                    <label class="form-label">Дата приема <span class="text-danger">*</span></label>
                    <input type="date" class="form-control" name="hire_date" required>
                </div>
                <div class="col-md-3">
                    <label class="form-label">Дата смены должности</label>
                    <input type="date" class="form-control" name="position_change_date">
                </div>
                <div class="col-md-3">
                    <label class="form-label">Пол <span class="text-danger">*</span></label>
                    <select class="form-select" name="gender" required>
                        <option value="">Не указан</option>
                        <option value="М">Мужской</option>
                        <option value="Ж">Женский</option>
                    </select>
                </div>
                <div class="col-md-3">
                    <label class="form-label">Рост <span class="text-danger">*</span></label>
                    <input class="form-control" name="height" placeholder="Например, 182" maxlength="10" required>
                </div>
            </div>
    '''
    content = content[:match.start(2)] + new_fields + content[match.end(2):]
    with open('app/templates/employees/list.html', 'w') as f:
        f.write(content)
    print("✅ Сетка полей в модалке создания выровнена (3 колонки + 4 колонки).")
else:
    print("⚠️ Не удалось найти блок с полями в модалке. Возможно, структура изменилась.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: align fields in employee creation modal"
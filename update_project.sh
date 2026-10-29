#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Меняем выпадающий список СИЗ на поиск с автодополнением в нормах..."

python3 - << 'PYEOF'
with open('app/templates/norms/list.html', 'r') as f:
    content = f.read()

# Заменяем select на input с datalist
old_select = '''            <div class="mb-3">
                <label class="form-label">Наименование СИЗ <span class="text-danger">*</span></label>
                <select class="form-select" name="ppe_item_id" id="norm-item-select" required>
                    <option value="">Загрузка...</option>
                </select>
            </div>'''

new_input = '''            <div class="mb-3">
                <label class="form-label">Наименование СИЗ <span class="text-danger">*</span></label>
                <input type="text" class="form-control" list="ppe-items-list" id="norm-item-input" placeholder="Начните вводить название..." required autocomplete="off">
                <datalist id="ppe-items-list">
                    <!-- Опции будут заполнены через JS -->
                </datalist>
                <input type="hidden" name="ppe_item_id" id="norm-item-id">
            </div>'''

if old_select in content:
    content = content.replace(old_select, new_input)
    with open('app/templates/norms/list.html', 'w') as f:
        f.write(content)
    print("✅ Поле ввода с автодополнением добавлено в шаблон.")
else:
    print("⚠️ Не удалось найти старый select в шаблоне.")
PYEOF

echo "📝 Обновляем логику в norms_list.js (фильтрация и выбор)..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# Удаляем старую логику с itemSelect и заменяем на новую
# Нам нужно переписать блоки, где используется itemSelect

# 1. Убираем переменную itemSelect и добавляем новые
old_vars = '''  const createForm = document.getElementById('create-norm-form');
  const itemSelect = document.getElementById('norm-item-select');
  const modalElement = document.getElementById('createNormModal');'''

new_vars = '''  const createForm = document.getElementById('create-norm-form');
  const itemInput = document.getElementById('norm-item-input');
  const itemIdInput = document.getElementById('norm-item-id');
  const itemsDatalist = document.getElementById('ppe-items-list');
  const modalElement = document.getElementById('createNormModal');'''

if old_vars in content:
    content = content.replace(old_vars, new_vars)
    print("✅ Переменные обновлены.")

# 2. В init() заменяем заполнение select на заполнение datalist
old_init = '''      allPpeItems = await API.get('/api/v1/ppe_items');
      
      itemSelect.innerHTML = '<option value="">Выберите СИЗ...</option>' + 
        allPpeItems.map(i => `<option value="${i.id}">${i.name} (${i.category?.name ?? ''})</option>`).join('');'''

new_init = '''      allPpeItems = await API.get('/api/v1/ppe_items');
      
      // Заполняем datalist
      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name} (${i.category?.name ?? ''})" data-id="${i.id}"></option>`
      ).join('');'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("✅ Инициализация обновлена (datalist).")

# 3. Добавляем обработчик выбора из datalist (при вводе)
# Нужно синхронизировать input и hidden id
# Добавим обработчик после posSelect.addEventListener
old_pos_listener = '''  posSelect.addEventListener('change', (e) => loadNorms(e.target.value));'''

new_pos_listener = '''  posSelect.addEventListener('change', (e) => loadNorms(e.target.value));

  // Обработчик ввода в поле СИЗ (поиск по datalist)
  itemInput.addEventListener('input', (e) => {
    const val = e.target.value;
    const option = Array.from(itemsDatalist.options).find(opt => opt.value === val);
    if (option) {
      itemIdInput.value = option.getAttribute('data-id');
    } else {
      itemIdInput.value = '';
    }
  });'''

if old_pos_listener in content:
    content = content.replace(old_pos_listener, new_pos_listener)
    print("✅ Обработчик выбора СИЗ добавлен.")

# 4. В openCreateModal сбрасываем input и hidden
old_reset = '''  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    // Сбрасываем выбранное СИЗ
    if (itemSelect) itemSelect.value = '';
  };'''

new_reset = '''  window.openCreateModal = () => {
    editingNormId = null;
    modalTitle.textContent = 'Новая норма выдачи';
    submitBtn.textContent = 'Добавить';
    createForm.reset();
    itemInput.value = '';
    itemIdInput.value = '';
  };'''

if old_reset in content:
    content = content.replace(old_reset, new_reset)
    print("✅ Сброс модалки обновлен.")

# 5. В editNorm заменяем установку itemSelect на itemInput и itemIdInput
old_edit = '''      // Заполняем форму
      itemSelect.value = norm.ppe_item_id;
      createForm.elements['wear_period_value'].value = norm.wear_period_value;'''

new_edit = '''      // Заполняем форму
      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);
      if (item) {
        itemInput.value = `${item.name} (${item.category?.name ?? ''})`;
        itemIdInput.value = item.id;
      }
      createForm.elements['wear_period_value'].value = norm.wear_period_value;'''

if old_edit in content:
    content = content.replace(old_edit, new_edit)
    print("✅ Редактирование обновлено (заполнение input).")

# 6. В submitForm берем ppe_item_id из hidden поля
old_submit = '''    const payload = {
      position_id: currentPositionId,
      ppe_item_id: Number(itemSelect.value),'''

new_submit = '''    const payload = {
      position_id: currentPositionId,
      ppe_item_id: Number(itemIdInput.value),'''

if old_submit in content:
    content = content.replace(old_submit, new_submit)
    print("✅ Отправка формы обновлена (берем id из hidden).")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! В нормах теперь поиск с автодополнением."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace select with datalist search in norms modal"
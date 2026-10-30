#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Добавляем выбор подразделения в модалку норм..."

# 1. Обновляем шаблон
python3 - << 'PYEOF'
with open('app/templates/norms/list.html', 'r') as f:
    content = f.read()

# Добавляем поле выбора подразделения перед полем должности
old_block = '''            <div class="mb-3">
                <label class="form-label">Должность <span class="text-danger">*</span></label>
                <select class="form-select" name="position_id" id="modal-position" required>
                    <option value="">Загрузка...</option>
                </select>
            </div>'''

new_block = '''            <div class="mb-3">
                <label class="form-label">Подразделение <span class="text-danger">*</span></label>
                <select class="form-select" id="modal-department" required>
                    <option value="">Выберите подразделение...</option>
                </select>
            </div>
            <div class="mb-3">
                <label class="form-label">Должность <span class="text-danger">*</span></label>
                <select class="form-select" name="position_id" id="modal-position" required>
                    <option value="">Сначала выберите подразделение</option>
                </select>
            </div>'''

if old_block in content:
    content = content.replace(old_block, new_block)
    with open('app/templates/norms/list.html', 'w') as f:
        f.write(content)
    print("✅ Шаблон обновлен (добавлено поле подразделения).")
else:
    print("⚠️ Не удалось найти блок должности в шаблоне.")
PYEOF

# 2. Обновляем JS
python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# 1. Добавляем переменные для подразделения и функций
if 'modalDepartment' not in content:
    content = content.replace(
        "const modalPosition = document.getElementById('modal-position');",
        "const modalDepartment = document.getElementById('modal-department');\n  const modalPosition = document.getElementById('modal-position');"
    )

# 2. Добавляем функцию buildHierarchy (если нет)
if 'function buildHierarchy' not in content:
    build_func = '''
  function buildHierarchy(depts, parentId = null, level = 0) {
    let result = [];
    const filtered = depts.filter(d => d.parent_id === parentId);
    filtered.sort((a, b) => a.name.localeCompare(b.name));
    for (const dept of filtered) {
      result.push({ ...dept, level });
      const children = buildHierarchy(depts, dept.id, level + 1);
      result = result.concat(children);
    }
    return result;
  }
'''
    content = content.replace(
        'async function loadData() {',
        build_func + '\n  async function loadData() {'
    )

# 3. В loadData загружаем подразделения и заполняем select в модалке
old_load = '''      allNorms = await API.get('/api/v1/position_ppe_norms');
      allPositions = await API.get('/api/v1/positions');
      allPpeItems = await API.get('/api/v1/ppe_items');'''

new_load = '''      allNorms = await API.get('/api/v1/position_ppe_norms');
      allPositions = await API.get('/api/v1/positions');
      allPpeItems = await API.get('/api/v1/ppe_items');
      const allDepartments = await API.get('/api/v1/departments');
      
      // Заполняем select подразделений в модалке (с иерархией)
      if (modalDepartment) {
        const hierarchy = buildHierarchy(allDepartments);
        modalDepartment.innerHTML = '<option value="">Выберите подразделение...</option>' +
          hierarchy.map(d => `<option value="${d.id}">${'↳ '.repeat(d.level)}${escapeHtml(d.name)}</option>`).join('');
      }'''

if old_load in content:
    content = content.replace(old_load, new_load)
    print("✅ loadData обновлен (загрузка подразделений для модалки).")

# 4. Добавляем обработчик изменения подразделения (фильтрация должностей)
if 'modalDepartment.addEventListener' not in content:
    handler = '''
  // Обработчик смены подразделения в модалке
  if (modalDepartment) {
    modalDepartment.addEventListener('change', async (e) => {
      const deptId = Number(e.target.value);
      if (!deptId) {
        modalPosition.innerHTML = '<option value="">Сначала выберите подразделение</option>';
        return;
      }
      
      try {
        const positions = await API.get('/api/v1/positions');
        const filtered = positions.filter(p => p.department_id === deptId);
        filtered.sort((a, b) => a.name.localeCompare(b.name));
        modalPosition.innerHTML = '<option value="">Выберите должность...</option>' +
          filtered.map(p => `<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('');
      } catch (err) {
        modalPosition.innerHTML = '<option value="">Ошибка загрузки</option>';
      }
    });
  }
'''
    content = content.replace(
        '  // Открытие модалки для создания',
        handler + '\n  // Открытие модалки для создания'
    )
    print("✅ Обработчик смены подразделения добавлен.")

# 5. В openCreateModal сбрасываем подразделение и должность
old_reset = '''    createForm.reset();
    itemInput.value = '';
    itemIdInput.value = '';
    modalPosition.value = '';'''

new_reset = '''    createForm.reset();
    itemInput.value = '';
    itemIdInput.value = '';
    modalDepartment.value = '';
    modalPosition.innerHTML = '<option value="">Сначала выберите подразделение</option>';'''

if old_reset in content:
    content = content.replace(old_reset, new_reset)
    print("✅ openCreateModal обновлен (сброс подразделения).")

# 6. В editNorm устанавливаем подразделение и загружаем должности
old_edit = '''      modalPosition.value = norm.position_id;
      
      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);'''

new_edit = '''      // Находим должность и её подразделение
      const pos = allPositions.find(p => p.id === norm.position_id);
      if (pos && pos.department_id && modalDepartment) {
        modalDepartment.value = pos.department_id;
        // Загружаем должности для этого подразделения
        const positions = await API.get('/api/v1/positions');
        const filtered = positions.filter(p => p.department_id === pos.department_id);
        filtered.sort((a, b) => a.name.localeCompare(b.name));
        modalPosition.innerHTML = '<option value="">Выберите должность...</option>' +
          filtered.map(p => `<option value="${p.id}">${escapeHtml(p.name)}</option>`).join('');
        modalPosition.value = norm.position_id;
      } else if (modalPosition) {
        modalPosition.value = norm.position_id;
      }
      
      const item = allPpeItems.find(i => i.id === norm.ppe_item_id);'''

if old_edit in content:
    content = content.replace(old_edit, new_edit)
    print("✅ editNorm обновлен (установка подразделения).")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! В модалке норм появился выбор подразделения."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "feat: add department selection (with hierarchy) to norm modal"
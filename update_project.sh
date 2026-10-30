#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Строим иерархию подразделений в выпадающем списке должностей (нормы)..."

python3 - << 'PYEOF'
with open('app/static/js/norms_list.js', 'r') as f:
    content = f.read()

# 1. Добавляем функцию для построения иерархии (если нет)
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
        'async function init() {',
        build_func + '\n  async function init() {'
    )

# 2. Обновляем инициализацию: загружаем подразделения и строим иерархию
old_init = '''  async function init() {
    try {
      const positions = await API.get('/api/v1/positions');
      posSelect.innerHTML = '<option value="">-- Выберите должность --</option>' + 
        positions.map(p => `<option value="${p.id}">${p.department?.name ?? ''} / ${p.name}</option>`).join('');

      allPpeItems = await API.get('/api/v1/ppe_items');
      
      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name}" data-id="${i.id}"></option>`
      ).join('');
    } catch (err) {
      window.showToast(`Ошибка инициализации: ${err.message}`, 'danger');
    }
  }'''

new_init = '''  async function init() {
    try {
      const positions = await API.get('/api/v1/positions');
      const departments = await API.get('/api/v1/departments');
      
      // Строим иерархию подразделений
      const hierarchy = buildHierarchy(departments);
      
      // Группируем должности по подразделениям
      const deptMap = {};
      hierarchy.forEach(d => { deptMap[d.id] = d; });
      
      // Сортируем должности по названию
      positions.sort((a, b) => a.name.localeCompare(b.name));
      
      posSelect.innerHTML = '<option value="">-- Выберите должность --</option>' + 
        positions.map(p => {
          const dept = deptMap[p.department_id];
          const deptPath = dept ? `${'↳ '.repeat(dept.level)}${dept.name}` : '—';
          return `<option value="${p.id}">${deptPath} / ${p.name}</option>`;
        }).join('');

      allPpeItems = await API.get('/api/v1/ppe_items');
      
      itemsDatalist.innerHTML = allPpeItems.map(i => 
        `<option value="${i.name}" data-id="${i.id}"></option>`
      ).join('');
    } catch (err) {
      window.showToast(`Ошибка инициализации: ${err.message}`, 'danger');
    }
  }'''

if old_init in content:
    content = content.replace(old_init, new_init)
    print("✅ init() обновлен (иерархия подразделений).")
else:
    print("⚠️ Не удалось найти init() в norms_list.js.")

with open('app/static/js/norms_list.js', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Список должностей в нормах теперь с иерархией."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: add department hierarchy to position dropdown in norms page"
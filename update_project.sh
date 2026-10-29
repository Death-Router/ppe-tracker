#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Обновляем тексты в навбаре (две строки)..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Заменяем тексты в навбаре
# Используем <br> для переноса строк, если нужно
replacements = [
    ('<span style="font-size: 0.7rem;">Категории</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">Категории<br>СИЗ</span>'),
    ('<span style="font-size: 0.7rem;">Наименования</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">СИЗ</span>'), # Просто СИЗ (коротко)
    ('<span style="font-size: 0.7rem;">Единицы</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">Единицы<br>измерения</span>'),
    ('<span style="font-size: 0.7rem;">Нормы</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">Нормы<br>выдачи</span>'),
    ('<span style="font-size: 0.7rem;">Подразделения</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">Подразделения</span>'), # Оставляем как есть, оно длинное и так перенесется
    ('<span style="font-size: 0.7rem;">Должности</span>', '<span style="font-size: 0.7rem; line-height: 1.1;">Должности</span>'),
]

for old, new in replacements:
    if old in content:
        content = content.replace(old, new)
        print(f"✅ Заменено: {old} -> {new}")

with open('app/templates/base.html', 'w') as f:
    f.write(content)
PYEOF

echo "🎨 Добавляем CSS для переноса строк и выравнивания..."

python3 - << 'PYEOF'
with open('app/static/css/app.css', 'r') as f:
    content = f.read()

if 'white-space: normal' not in content:
    content += '''
/* Разрешаем перенос текста в навбаре и выравниваем по центру */
.navbar-nav .nav-link span {
    white-space: normal;
    text-align: center;
    display: block;
    line-height: 1.2;
    margin-top: 2px;
}
'''
    with open('app/static/css/app.css', 'w') as f:
        f.write(content)
    print("✅ CSS для переноса строк добавлен.")
else:
    print("ℹ️ CSS уже есть.")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Надписи обновлены и переносятся на две строки."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: update navbar labels with multi-line support"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Заменяем иконку кубика на каску в навбаре..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# SVG-код каски (Phosphor Icons, MIT License)
helmet_svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="1.2rem" height="1.2rem" fill="currentColor" class="d-block mx-auto mb-1"><path d="M228,148.4V136a100.41,100.41,0,0,0-64-93.3V40a20,20,0,0,0-20-20H112A20,20,0,0,0,92,40v2.7A100.41,100.41,0,0,0,28,136v12.4A20,20,0,0,0,12,168v24a20,20,0,0,0,20,20H224a20,20,0,0,0,20-20V168A20,20,0,0,0,228,148.4ZM204,136v12H164V69.07A76.35,76.35,0,0,1,204,136ZM140,44V148H116V44ZM92,69.07V148H52V136A76.35,76.35,0,0,1,92,69.07ZM220,188H36V172H220Z"/></svg>'''

# Ищем иконку кубика (bi-box-seam) и заменяем её на SVG каски
# Наша иконка находится внутри ссылки на /ppe
old_icon = '<i class="bi bi-box-seam d-block" style="font-size: 1.2rem;"></i>'
new_icon = helmet_svg

if old_icon in content:
    content = content.replace(old_icon, new_icon)
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Иконка кубика заменена на каску (SVG).")
else:
    print("⚠️ Не удалось найти иконку кубика в base.html. Возможно, структура изменилась.")

PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! В навбаре теперь иконка каски."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace box icon with hard hat icon in navbar"
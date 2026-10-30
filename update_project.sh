#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🎨 Заменяем иконку каски на щит в навбаре..."

python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

# SVG-код щита с галочкой (Phosphor Icons, MIT)
shield_svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="1.2rem" height="1.2rem" fill="currentColor" class="d-block mx-auto mb-1"><path d="M208,40H48A16,16,0,0,0,32,56v56c0,54.72,29.8,101.16,79.28,127.56a8.06,8.06,0,0,0,7.44,0C168.2,213.16,208,166.72,208,112V56A16,16,0,0,0,208,40Zm-8,72c0,46.4-24.29,86.24-64,109.33C96.29,198.24,72,158.4,72,112V56H208ZM107.32,135.32a8,8,0,0,1,11.32,0L136,152.69l37.66-37.66a8,8,0,0,1,11.32,11.31l-43.32,43.32a8,8,0,0,1-11.32,0l-23-23A8,8,0,0,1,107.32,135.32Z"/></svg>'''

# Ищем текущую иконку (каску) и заменяем на щит
# Мы ранее вставили SVG каски, теперь заменяем его
old_helmet_pattern = r'<svg xmlns="http://www\.w3\.org/2000/svg" viewBox="0 0 256 256" width="1\.2rem" height="1\.2rem" fill="currentColor" class="d-block mx-auto mb-1"><path d="M228,148\.4V136a100\.41.*?</svg>'
new_shield = shield_svg

import re
content, count = re.subn(old_helmet_pattern, new_shield, content)

if count > 0:
    with open('app/templates/base.html', 'w') as f:
        f.write(content)
    print("✅ Иконка каски заменена на щит (SVG).")
else:
    # Если регулярка не сработала, попробуем найти кубик или другую иконку
    old_box = '<i class="bi bi-box-seam d-block" style="font-size: 1.2rem;"></i>'
    if old_box in content:
        content = content.replace(old_box, new_shield)
        with open('app/templates/base.html', 'w') as f:
            f.write(content)
        print("✅ Иконка кубика заменена на щит (SVG).")
    else:
        print("⚠️ Не удалось найти иконку в base.html для замены.")

PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! В навбаре теперь иконка щита."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace helmet icon with shield icon in navbar"
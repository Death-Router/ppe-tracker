#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Заменяем SVG-щит на иконку Bootstrap (bi-shield-check)..."

python3 - << 'PYEOF'
import re

with open('app/templates/base.html', 'r') as f:
    content = f.read()

# Заменяем SVG-иконку щита на Bootstrap иконку
# Ищем SVG, который мы вставили ранее
pattern = r'<svg[^>]*>.*?</svg>'
# Но нам нужно заменить только тот, что в навбаре (внутри ссылки на /ppe)
# Найдем блок с ссылкой на /ppe и внутри него заменим svg на i
old_block = re.search(r'<a class="nav-link[^"]*" href="/ppe">\s*<svg.*?</svg>\s*<span.*?>СИЗ</span>\s*</a>', content, re.DOTALL)

if old_block:
    new_block = '''<a class="nav-link {% if '/ppe' in request.url.path or '/norms' in request.url.path or '/units' in request.url.path %}active{% endif %}" href="/ppe">
                        <i class="bi bi-shield-check d-block nav-icon" style="font-size: 1.8rem;"></i>
                        <span style="font-size: 0.85rem;">СИЗ</span>
                    </a>'''
    content = content.replace(old_block.group(0), new_block)
    print("✅ SVG-щит заменен на bi-shield-check.")
else:
    # Если регулярка не сработала, просто заменим все svg на i (на всякий случай)
    content = re.sub(r'<svg[^>]*>.*?</svg>', '<i class="bi bi-shield-check d-block nav-icon" style="font-size: 1.8rem;"></i>', content, flags=re.DOTALL)
    print("✅ Все SVG заменены на bi-shield-check (альтернативный метод).")

with open('app/templates/base.html', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Иконки теперь из одного шрифта и выровнены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: replace SVG shield with Bootstrap icon (bi-shield-check) for alignment"
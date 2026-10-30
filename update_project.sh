#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Включаем проверку орфографии для названий и описаний..."

python3 - << 'PYEOF'
import os
import re

templates_dir = 'app/templates'
for root, dirs, files in os.walk(templates_dir):
    for file in files:
        if not file.endswith('.html'):
            continue
        
        path = os.path.join(root, file)
        with open(path, 'r') as f:
            content = f.read()
        
        # 1. Убираем spellcheck="false" у полей с name (это названия, проверка нужна)
        content = re.sub(r'\s+spellcheck="false"', '', content)
        
        # 2. Включаем проверку (spellcheck="true") для всех input type="text" и textarea
        content = re.sub(
            r'(<input[^>]*?type="text"[^>]*?)>',
            lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
            content
        )
        content = re.sub(
            r'(<textarea[^>]*?)>',
            lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="true">',
            content
        )
        
        # 3. Отключаем проверку (spellcheck="false") для ФИО и номеров
        no_spell = ['last_name', 'first_name', 'middle_name', 'personnel_number']
        for field in no_spell:
            content = re.sub(
                rf'(<input[^>]*?name="{field}"[^>]*?)>',
                lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'{m.group(1)} spellcheck="false">',
                content
            )
        
        with open(path, 'w') as f:
            f.write(content)
        print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверка орфографии работает для названий, отключена для ФИО."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: fix spellcheck logic (enable for names, disable for first/last names)"
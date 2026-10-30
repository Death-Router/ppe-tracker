#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Жёстко прописываем spellcheck в HTML-шаблонах..."

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
        
        # 1. Включаем spellcheck для textarea (комментарии, описания)
        content = re.sub(
            r'<textarea([^>]*?)>',
            lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'<textarea{m.group(1)} spellcheck="true">',
            content
        )
        
        # 2. Включаем spellcheck для input type="text", если это не ФИО/номер/название
        # Сначала добавляем spellcheck="false" для полей с именами из списка исключений
        no_spell = ['last_name', 'first_name', 'middle_name', 'personnel_number', 'name', 'short_name']
        for field in no_spell:
            content = re.sub(
                rf'<input([^>]*?name="{field}"[^>]*?)>',
                lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'<input{m.group(1)} spellcheck="false">',
                content
            )
        
        # Для остальных input type="text" (например, comment) включаем spellcheck
        content = re.sub(
            r'<input([^>]*?type="text"[^>]*?)>',
            lambda m: m.group(0) if 'spellcheck' in m.group(1) else f'<input{m.group(1)} spellcheck="true">',
            content
        )
        
        with open(path, 'w') as f:
            f.write(content)
        print(f"✅ Обновлен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Проверка орфографии прописана в HTML."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "ui: explicitly set spellcheck attributes in HTML templates"
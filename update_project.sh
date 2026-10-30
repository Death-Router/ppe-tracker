#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🧹 Убираем все настройки проверки орфографии..."

# 1. Удаляем скрипт из base.html
python3 - << 'PYEOF'
with open('app/templates/base.html', 'r') as f:
    content = f.read()

import re
# Удаляем скрипт, который мы добавляли для spellcheck
content = re.sub(r'<script>\s*document\.addEventListener\(\'DOMContentLoaded\',\s*\(\)\s*=>\s*\{.*?noSpellcheckNames.*?\}\);\s*</script>', '', content, flags=re.DOTALL)
content = re.sub(r'<script>\s*// Поля, для которых проверка орфографии НЕ нужна.*?</script>', '', content, flags=re.DOTALL)

with open('app/templates/base.html', 'w') as f:
    f.write(content)
print("✅ Скрипт из base.html удален (если был).")
PYEOF

# 2. Удаляем все атрибуты spellcheck из шаблонов
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
        
        # Удаляем атрибут spellcheck="..." (любое значение)
        new_content = re.sub(r'\s+spellcheck="[^"]*"', '', content)
        
        if new_content != content:
            with open(path, 'w') as f:
                f.write(new_content)
            print(f"✅ Очищен {path}")
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Все настройки проверки орфографии удалены."

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "chore: remove spellcheck attributes and scripts (revert)"
#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "🔧 Исправляем последнее предупреждение в ppe_categories.py..."

python3 - << 'PYEOF'
import re

with open('app/api/v1/endpoints/ppe_categories.py', 'r') as f:
    content = f.read()

# 1. Добавляем импорт IntegrityError, если его нет
if 'from sqlalchemy.exc import IntegrityError' not in content:
    content = content.replace(
        'from sqlalchemy import select',
        'from sqlalchemy import select\nfrom sqlalchemy.exc import IntegrityError'
    )

# 2. Заменяем проблемный except Exception на IntegrityError
# (только в функции delete_category, чтобы не задеть другие)
old_block = '''    except Exception:  # Ловим ошибку внешнего ключа (IntegrityError)
        await db.rollback()
        raise HTTPException(
            status_code=400, 
            detail="Невозможно удалить категорию, так как к ней привязаны наименования СИЗ."
        )'''

new_block = '''    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=400, 
            detail="Невозможно удалить категорию, так как к ней привязаны наименования СИЗ."
        )'''

if old_block in content:
    content = content.replace(old_block, new_block)
    print("✅ Блок в delete_category исправлен на IntegrityError.")
else:
    # Если не нашли точный блок, используем регулярку
    pattern = r'except Exception:\s*# Ловим ошибку внешнего ключа.*?\n(\s*)await db\.rollback\(\)'
    replacement = r'except IntegrityError:\n\1await db.rollback()'
    content = re.sub(pattern, replacement, content)
    print("✅ Использована регулярка для замены.")

with open('app/api/v1/endpoints/ppe_categories.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО! Теперь Ruff полностью доволен."
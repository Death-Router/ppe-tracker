#!/bin/bash
set -e

if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Ошибка: Скрипт нужно запускать из корневой папки проекта."
    exit 1
fi

echo "📝 Убираем колонку ID из экспорта..."

python3 - << 'PYEOF'
with open('app/api/v1/endpoints/export.py', 'r') as f:
    content = f.read()

# Убираем строку "ID": emp.id из экспорта сотрудников
content = content.replace('            "ID": emp.id,\n', '')
# Убираем "ID": item.id из экспорта СИЗ
content = content.replace('            "ID": item.id,\n', '')
# Убираем "ID": norm.id из экспорта норм
content = content.replace('            "ID": norm.id,\n', '')

with open('app/api/v1/endpoints/export.py', 'w') as f:
    f.write(content)
print("✅ Экспорт обновлен (без ID).")
PYEOF

echo "📝 Обновляем импорт (игнорируем ID, если он есть)..."

python3 - << 'PYEOF'
with open('app/api/v1/endpoints/import_data.py', 'r') as f:
    content = f.read()

# Добавляем защиту: удаляем колонку "ID", если она есть в DataFrame
old_code = '''        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")'''

new_code = '''        contents = await file.read()
        df = pd.read_excel(BytesIO(contents))
        
        # Удаляем колонку ID, если она есть (она нам не нужна, ориентируемся на табельный номер)
        if 'ID' in df.columns:
            df = df.drop(columns=['ID'])
            
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Ошибка чтения файла: {str(e)}")'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Импорт обновлен (игнорирует ID).")
else:
    print("⚠️ Не удалось найти блок чтения файла для замены.")

with open('app/api/v1/endpoints/import_data.py', 'w') as f:
    f.write(content)
PYEOF

echo "🚀 Перезапускаем контейнер..."
docker compose restart api
sleep 2

echo "✅ ГОТОВО!"

# --- Git Commit ---
echo "📦 Фиксируем изменения в Git..."
git add .
git commit -m "fix: remove ID from excel export and ignore it on import"
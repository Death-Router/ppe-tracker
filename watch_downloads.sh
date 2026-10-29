#!/bin/bash

DOWNLOADS_DIR="/mnt/c/Users/Vagur/Downloads"
TARGET_FILE="update_project.sh"
PROJECT_DIR="/home/vagur/projects/ppe-tracker"

echo "👀 Запущен мониторинг папки: $DOWNLOADS_DIR"
echo "📂 Целевой файл: $PROJECT_DIR/$TARGET_FILE"
echo "⏳ Ожидание новых файлов... (Ctrl+C для выхода)"

LAST_COPIED=""

# Бесконечный цикл
while true; do
    # Ищем самый новый файл, начинающийся на deepseek
    LATEST_FILE=$(ls -t "$DOWNLOADS_DIR"/deepseek* 2>/dev/null | head -n 1)

    if [ -n "$LATEST_FILE" ]; then
        # Проверяем, не тот ли это файл, который мы уже копировали
        if [ "$LATEST_FILE" != "$LAST_COPIED" ]; then
            echo "----------------------------------------"
            echo "📥 Обнаружен новый файл: $(basename "$LATEST_FILE")"
            
            # Пауза, чтобы файл точно докачался
            sleep 1
            
            # Удаляем старый файл, чтобы обойти Permission denied
            rm -f "$PROJECT_DIR/$TARGET_FILE"
            
            # Копируем
            cp "$LATEST_FILE" "$PROJECT_DIR/$TARGET_FILE"
            
            # Принудительно даем права на исполнение
            chmod +x "$PROJECT_DIR/$TARGET_FILE"
            
            # Удаляем оригинал
            rm "$LATEST_FILE"
            echo "✅ Скопировано в $TARGET_FILE и удален оригинал."
            
            # Запоминаем, что этот файл уже обработан
            LAST_COPIED="$LATEST_FILE"
            
            # Запускаем
            echo "🚀 Запускаем update_project.sh..."
            cd "$PROJECT_DIR" && ./update_project.sh
            echo "🏁 Скрипт завершил работу."
            echo "----------------------------------------"
            echo "⏳ Ожидание новых файлов..."
        fi
    fi
    
    # Пауза перед следующей проверкой (2 секунды)
    sleep 2
done
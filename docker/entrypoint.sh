#!/bin/sh
# Точка входа прод-образа.
#
# Миграции по умолчанию НЕ применяются: прод-база обычно уже на голове, и
# лишний upgrade при каждом старте — лишний риск. Схема с нуля теперь
# собирается целиком (PROJECT.md, ловушка 8 исправлена), поэтому для пустой
# базы достаточно AUTO_MIGRATE=1: шаг `alembic upgrade head` выполнится с
# повторами, дожидаясь готовности БД.
set -e

if [ "${AUTO_MIGRATE:-0}" = "1" ]; then
    attempt=1
    while [ "$attempt" -le 30 ]; do
        if alembic upgrade head; then
            echo "миграции применены (попытка $attempt)"
            break
        fi
        echo "миграции не прошли (попытка $attempt), ждём базу 2 с"
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ "$attempt" -gt 30 ]; then
        echo "не удалось применить миграции: база не готова или цепочка порвана" >&2
        exit 1
    fi
fi

exec "$@"

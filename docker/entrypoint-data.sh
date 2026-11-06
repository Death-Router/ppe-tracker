#!/bin/sh
# Точка входа образа с данными (dockerfile.data).
#
# Задача — довезти dev-данные до пустой прод-базы и только потом отдать
# управление штатному entrypoint.sh базового образа.
#
#   AUTO_MIGRATE=1  развернуть схему миграциями (как в прод-образе)
#   FORCE=1         залить дамп поверх непустой базы (удаляет данные!)
#
# Дамп применяется один раз: после успеха лежит маркер, поэтому повторный
# старт контейнера не накатывает данные поверх пользовательских правок.
set -e

DUMP=${DUMP_PATH:-/app/data/dump.sql}
MARKER=${DUMP_MARKER:-/app/data/.dump-loaded}
# Сколько раз по 2 с ждать базу и миграции
WAIT_ATTEMPTS=${WAIT_ATTEMPTS:-90}

log() { echo "data-image: $*"; }

if [ ! -f "$DUMP" ]; then
    echo "data-image: нет дампа $DUMP — образ собран без данных?" >&2
    exit 1
fi

# 1. База отвечает? Проверяем через приложение: те же настройки подключения,
# никаких лишних переменных и утилит. Хост может ещё подниматься после
# depends_on: service_healthy, если контейнер запущен вручную.
attempt=1
while :; do
    if python -c "
import asyncio
import sys

from sqlalchemy import text

from app.db.session import async_session_maker


async def ping() -> None:
    async with async_session_maker() as db:
        await db.execute(text('SELECT 1'))


try:
    asyncio.run(ping())
except Exception as exc:  # noqa: BLE001 - любая ошибка значит «не готова»
    print(exc, file=sys.stderr)
    sys.exit(1)
"; then
        log "база доступна (попытка $attempt)"
        break
    fi
    if [ "$attempt" -ge "$WAIT_ATTEMPTS" ]; then
        echo "data-image: база не ответила за $((WAIT_ATTEMPTS * 2)) с" >&2
        exit 1
    fi
    log "база не готова (попытка $attempt), ждём 2 с"
    attempt=$((attempt + 1))
    sleep 2
done

# 2. Схема. Без неё не работают ни psql-дамп (COPY в несуществующие таблицы),
# ни проверка «база пустая».
if [ "${AUTO_MIGRATE:-0}" = "1" ]; then
    attempt=1
    while :; do
        if alembic upgrade head; then
            log "миграции применены (попытка $attempt)"
            break
        fi
        if [ "$attempt" -ge "$WAIT_ATTEMPTS" ]; then
            echo "data-image: alembic upgrade head не прошёл за $((WAIT_ATTEMPTS * 2)) с" >&2
            exit 1
        fi
        log "миграции не прошли (попытка $attempt), ждём 2 с"
        attempt=$((attempt + 1))
        sleep 2
    done
else
    log "AUTO_MIGRATE не включён: считаю, что схему развернул базовый образ"
fi

# 3. Дамп уже применялся в этом томе?
if [ -f "$MARKER" ]; then
    log "дамп уже применён ранее ($MARKER) — данные не перезаливаем"
    exec /usr/local/bin/entrypoint.sh "$@"
fi

# 4. Страховка от затирания живых данных: дамп идёт только в пустую базу.
# Иначе контейнер, запущенный на чужом томе, уничтожит то, что там лежит.
rows=$(python -c "
import asyncio

from sqlalchemy import text

from app.db.session import async_session_maker


async def count() -> int:
    async with async_session_maker() as db:
        result = await db.execute(text('SELECT count(*) FROM users'))
        return int(result.scalar_one())


print(asyncio.run(count()))
")

if [ "$rows" != "0" ]; then
    echo "data-image: в базе уже есть данные (пользователей: $rows)." >&2
    echo "data-image: залить поверх можно только с FORCE=1 — это удалит текущие данные." >&2
    if [ "${FORCE:-0}" != "1" ]; then
        exit 1
    fi
    log "FORCE=1: перезаливаю данные поверх существующих"
fi

# 5. Заливаем дамп одной транзакцией: ошибка в середине не оставит базу
# наполовину заполненной и маркер «применено».
#
# Подключение — через export PGHOST/PGUSER/PGPASSWORD/PGDATABASE, а не через
# DATABASE_URL: в окружении контейнера его нет (в приложении это свойство
# settings.database_url), а голый psql ищет локальный сокет и падает с
# "No such file or directory" (проверено).
#
# export, а не префикс PGHOST=... перед psql: префиксные присваивания
# работают, но в связке с `if !` и многострочным вызовом читаются хуже,
# и одна опечатка в цепочке делает их недействительными молча.
export PGHOST="$POSTGRES_HOST"
export PGPORT="${POSTGRES_PORT:-5432}"
export PGUSER="$POSTGRES_USER"
export PGPASSWORD="$POSTGRES_PASSWORD"
export PGDATABASE="$POSTGRES_DB"

log "заливаю $DUMP в базу"
if ! psql \
        --single-transaction \
        --set ON_ERROR_STOP=1 \
        --quiet \
        --file "$DUMP"; then
    echo "data-image: дамп не применился, изменения откачены" >&2
    exit 1
fi

touch "$MARKER"
log "данные залиты, маркер записан"

exec /usr/local/bin/entrypoint.sh "$@"

#!/bin/sh
# make-data-image.sh — собрать образ PPE Tracker и упаковать его для переноса.
#
# По умолчанию собирается ЧИСТЫЙ образ: схема развернётся миграциями при
# первом старте, данных нет. С переносом данных из dev-базы — флаг --with-data.
# Флаг --save упаковывает результат в .tar (или .tar.gz), который загружается
# на другой машине одной командой: docker load -i файл.tar
#
# Запуск из корня клона:
#
#   ./make-data-image.sh                          # чистый образ
#   ./make-data-image.sh --with-data              # + данные из dev-базы
#   ./make-data-image.sh --save                   # чистый + файл для переноса
#   ./make-data-image.sh --with-data --save --gzip
#   ./make-data-image.sh --with-data -d dump.sql  # данные из готового дампа
#
# Требования: docker (Докер Desktop на Windows или нативный Docker на Linux).
# Скрипт — POSIX sh: bash-измов нет, запускается и через dash.
#
# Права на исполнение: .gitattributes в проекте фиксирует LF, но бит +x
# переживает не каждый перенос (Windows-клон, архив, копирование файла) —
# поэтому если ./make-data-image.sh говорит "Permission denied", достаточно
# `chmod +x make-data-image.sh` или `sh make-data-image.sh`.

set -eu

# --- Значения по умолчанию -----------------------------------------------
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.yml}
DEV_DB_SERVICE=${DEV_DB_SERVICE:-db}
PROD_IMAGE=${PROD_IMAGE:-ppe-tracker-api:prod}
DATA_IMAGE=${DATA_IMAGE:-ppe-tracker-api:data}
DUMP_FILE=
WITH_DATA=0
KEEP_DUMP=0
SAVE=0
SAVE_PATH=
GZIP=0

usage() {
    cat <<'EOF'
make-data-image.sh — собрать образ PPE Tracker и упаковать для переноса

Использование:
  ./make-data-image.sh [опции]

Образ:
      --with-data      включить данные из dev-базы (по умолчанию — чистый образ)
  -d, --dump ФАЙЛ      взять готовый .sql вместо pg_dump из dev-базы
                       (подразумевает --with-data)
  -b, --base ОБРАЗ     тег прод-образа (по умолчанию ppe-tracker-api:prod)
  -t, --tag ОБРАЗ      тег образа с данными (по умолчанию ppe-tracker-api:data)
  -k, --keep-dump      не удалять временный каталог с дампом после сборки

Перенос на другую машину:
  -s, --save [ФАЙЛ]    упаковать образ в tar (docker save); без пути —
                       ppe-tracker-api-<tag>.tar рядом со скриптом
      --gzip           сжать файл: .tar.gz (по умолчанию без сжатия)

Прочее:
  -h, --help           эта справка

Что происходит:
  чистый образ:  docker build -f dockerfile.prod  →  ppe-tracker-api:prod
  с данными:     плюс pg_dump dev-базы и слой с дампом  →  ...:data

Внутри образа с данными дамп лежит в /app/data/dump.sql и применяется при
первом старте на ПУСТОЙ базе; повторно не накатывается (маркер .dump-loaded).
Перезалить поверх живых данных: FORCE=1.

Схема в обоих случаях разворачивается миграциями (alembic upgrade head) —
AUTO_MIGRATE=1 при первом старте.
EOF
}

# --- Разбор аргументов ----------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--tag)       DATA_IMAGE=${2:?--tag требует значения}; shift 2 ;;
        -b|--base)      PROD_IMAGE=${2:?--base требует значения}; shift 2 ;;
        -d|--dump)      DUMP_FILE=${2:?--dump требует значения}; WITH_DATA=1; shift 2 ;;
        -k|--keep-dump) KEEP_DUMP=1; shift ;;
        --with-data)    WITH_DATA=1; shift ;;
        --gzip)         GZIP=1; shift ;;
        -s|--save)
            # Путь необязателен: следующий аргумент берём, только если это
            # не опция и он похож на файл (а не на тег образа)
            SAVE=1
            case "${2:-}" in
                ""|-*) ;;
                *:*) shift ;;  # похоже на тег — не трогаем
                *) SAVE_PATH=$2; shift ;;
            esac
            shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Неизвестный аргумент: $1 (см. --help)" >&2; exit 2 ;;
    esac
done

# --- Вывод ----------------------------------------------------------------
if [ -t 1 ]; then
    C_STEP=$(printf '\033[36m'); C_OK=$(printf '\033[32m')
    C_WARN=$(printf '\033[33m'); C_ERR=$(printf '\033[31m'); C_OFF=$(printf '\033[0m')
else
    C_STEP=; C_OK=; C_WARN=; C_ERR=; C_OFF=
fi
step() { printf '%s==>%s %s\n' "$C_STEP" "$C_OFF" "$*"; }
ok()   { printf '%s    %s%s\n' "$C_OK" "$*" "$C_OFF"; }
warn() { printf '%s    %s%s\n' "$C_WARN" "$*" "$C_OFF"; }
die()  { printf '%s    %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

# Читает переменную из .env (последнее вхождение), без кавычек и \r
env_value() {
    sed -n "s/^$1=//p" .env 2>/dev/null | tr -d '\r' | tail -1
}

# --- Проверки окружения ---------------------------------------------------
step "Проверяю окружение"

command -v docker >/dev/null 2>&1 || die "нет docker в PATH"
docker info >/dev/null 2>&1 || die "демон Docker не отвечает (запущен ли Docker Desktop?)"

for f in dockerfile.prod requirements.txt; do
    [ -f "$f" ] || die "нет $f: запускайте скрипт из корня клона"
done
if [ "$WITH_DATA" = "1" ]; then
    [ -f dockerfile.data ] || die "нет dockerfile.data (нужен для --with-data)"
    [ -f docker/entrypoint-data.sh ] || die "нет docker/entrypoint-data.sh"
fi

ok "docker: $(docker --version | sed 's/^Docker version //; s/,.*//')"
if [ "$WITH_DATA" = "1" ]; then
    ok "режим: с данными из dev-базы"
else
    ok "режим: чистый образ, без данных"
fi

# --- 1. Dev-база (только с данными) ---------------------------------------
TMP_DIR=
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        if [ "$KEEP_DUMP" = "1" ]; then
            warn "дамп оставлен: $TMP_DIR/data/dump.sql"
        else
            # Дамп — персональные данные сотрудников. Во временном каталоге
            # ему нечего делать: удаляем целиком, а не только затираем.
            rm -rf "$TMP_DIR"
        fi
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$WITH_DATA" = "1" ] && [ -z "$DUMP_FILE" ]; then
    docker compose version >/dev/null 2>&1 || die "нужен docker compose v2 для pg_dump"
    if [ ! -f .env ]; then
        warn "нет .env — dev-база не стартует с пустыми POSTGRES_*."
        warn "Сделайте: cp .env.example .env и заполните SECRET_KEY и пароли."
    fi

    step "Поднимаю dev-базу ($DEV_DB_SERVICE)"
    if ! docker compose -f "$COMPOSE_FILE" up -d "$DEV_DB_SERVICE" >/dev/null; then
        die "не удалось поднять dev-базу: docker compose -f $COMPOSE_FILE up -d $DEV_DB_SERVICE"
    fi

    # Учётные данные — у самого контейнера: compose может читать окружение из
    # другого файла, а .env с переменными dev-базы может отсутствовать
    dev_user=$(docker compose -f "$COMPOSE_FILE" exec -T "$DEV_DB_SERVICE" printenv POSTGRES_USER 2>/dev/null | tr -d '\r\n' || true)
    dev_db=$(docker compose -f "$COMPOSE_FILE" exec -T "$DEV_DB_SERVICE" printenv POSTGRES_DB 2>/dev/null | tr -d '\r\n' || true)

    [ -n "$dev_user" ] || dev_user=$(env_value POSTGRES_USER)
    [ -n "$dev_db" ] || dev_db=$(env_value POSTGRES_DB)
    [ -n "$dev_user" ] || die "не удалось узнать POSTGRES_USER dev-базы"
    [ -n "$dev_db" ] || die "не удалось узнать POSTGRES_DB dev-базы"

    step "Жду готовности dev-базы"
    attempt=1
    while :; do
        if docker compose -f "$COMPOSE_FILE" exec -T "$DEV_DB_SERVICE" \
                pg_isready -U "$dev_user" -d "$dev_db" >/dev/null 2>&1; then
            ok "база готова: $dev_user@$dev_db"
            break
        fi
        if [ "$attempt" -ge 30 ]; then
            die "dev-база не готова за 30 попыток (~30 с)"
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
fi

# --- 2a. Чистый образ -----------------------------------------------------
if [ "$WITH_DATA" != "1" ]; then
    step "Собираю образ $PROD_IMAGE"
    docker build -f dockerfile.prod -t "$PROD_IMAGE" . || die "сборка $PROD_IMAGE не удалась"
    ok "образ готов: $PROD_IMAGE"
    IMAGE_TO_SAVE=$PROD_IMAGE
else
    # --- 2b. Дамп и образ с данными ---------------------------------------
    TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ppe-data.XXXXXX")
    mkdir -p "$TMP_DIR/data"

    # Точка входа образа с данными кладётся в контекст сборки по тому же пути,
    # что в репозитории: dockerfile.data читает её относительно контекста, а не
    # репозитория. Сохраняем docker/, а не кладём в корень, — тогда работают обе
    # версии dockerfile.data (с "docker/entrypoint-data.sh" и без префикса).
    mkdir -p "$TMP_DIR/docker"
    cp docker/entrypoint-data.sh "$TMP_DIR/docker/entrypoint-data.sh"
    cp docker/entrypoint-data.sh "$TMP_DIR/entrypoint-data.sh"
    chmod 0755 "$TMP_DIR/docker/entrypoint-data.sh" "$TMP_DIR/entrypoint-data.sh"

    if [ -n "$DUMP_FILE" ]; then
        [ -f "$DUMP_FILE" ] || die "нет файла дампа: $DUMP_FILE"
        step "Беру готовый дамп $DUMP_FILE"
        cp "$DUMP_FILE" "$TMP_DIR/data/dump.sql"
    else
        step "Снимаю pg_dump из dev-базы"

        # Только ДАННЫЕ: --data-only. Схему в целевой базе целиком создаёт
        # alembic (entrypoint-data.sh делает `alembic upgrade head` до заливки),
        # поэтому любой DDL в дампе — лишний и опасный. Проверено на практике,
        # три попытки наступили на одну и ту же ловушку:
        #   - с --clean: "cannot drop constraint ppe_size_groups_pkey ... because
        #     other objects depend on it" (DROP-ы ломаются о зависимости dev-базы);
        #   - без --clean: "relation \"departments\" already exists" (дамп создаёт
        #     таблицы, которые alembic уже создал);
        #   - построчный grep по alembic_version: обрезанный DDL, "syntax error
        #     at or near version_num".
        # С --data-only остаются только вставки данных, разбора текста нет.
        #
        # Вставки — INSERT ... ON CONFLICT DO NOTHING, а не COPY.
        # Причина: миграции b7e1c93d5a24, d5a8f21c4e37 и c4d9e2b71f30 САМИ
        # создают справочные размеры (ppe_size_groups, ppe_sizes) с
        # фиксированными id=1,2,… В dev-базе эти же строки лежат с теми же id,
        # а сверх них есть группы, добавленные вручную через интерфейс.
        # COPY падал с "duplicate key ... (id)=(1) already exists", а
        # исключение справочников из дампа роняло FK "size_group_id=(10) is
        # not present". ON CONFLICT DO NOTHING решает оба случая.
        #
        # --on-conflict-do-nothing требует PostgreSQL 12+ (у нас 16).
        # --column-inserts обязателен: ON CONFLICT неприменим к COPY.
        if ! docker compose -f "$COMPOSE_FILE" exec -T "$DEV_DB_SERVICE" \
                pg_dump -U "$dev_user" -d "$dev_db" \
                --data-only \
                --column-inserts \
                --on-conflict-do-nothing \
                --no-owner --no-privileges \
                --exclude-table=alembic_version \
                > "$TMP_DIR/data/dump.sql"; then
            die "pg_dump не удался"
        fi

        dump_bytes=$(wc -c < "$TMP_DIR/data/dump.sql" | tr -d ' ')
        [ "$dump_bytes" -gt 1024 ] || die "дамп подозрительно мал ($dump_bytes байт) — dev-база пуста?"

        # Страховки: DDL в дампе быть не должно, ссылок на alembic_version тоже.
        if grep -qE '^(CREATE|ALTER|DROP) ' "$TMP_DIR/data/dump.sql"; then
            die "в дампе есть DDL — --data-only не сработал"
        fi
        if grep -q 'alembic_version' "$TMP_DIR/data/dump.sql"; then
            die "в дампе остались строки alembic_version — исключение не сработало"
        fi
    fi

    # Права: внутри контейнера читает app (uid 10001), скрипт может работать
    # под другим uid — выравниваем явно.
    chmod 0644 "$TMP_DIR/data/dump.sql"
    ok "дамп готов: $(wc -c < "$TMP_DIR/data/dump.sql" | tr -d ' ') байт"

    step "Собираю базовый образ $PROD_IMAGE"
    docker build -f dockerfile.prod -t "$PROD_IMAGE" . || die "сборка $PROD_IMAGE не удалась"
    ok "базовый образ готов"

    step "Собираю образ с данными $DATA_IMAGE"
    docker build -f dockerfile.data \
        --build-arg "BASE_IMAGE=$PROD_IMAGE" \
        -t "$DATA_IMAGE" "$TMP_DIR" \
        || die "сборка $DATA_IMAGE не удалась"
    ok "образ с данными готов"

    # Проверка, что дамп действительно лёг в образ, а не потерялся в контексте:
    # COPY молча пройдёт, только если файла не было.
    if ! docker run --rm --entrypoint sh "$DATA_IMAGE" \
            -c 'test -s /app/data/dump.sql' >/dev/null 2>&1; then
        die "в образе нет /app/data/dump.sql — дамп не попал в контекст сборки"
    fi
    ok "дамп на месте внутри образа"
    IMAGE_TO_SAVE=$DATA_IMAGE
fi

# --- 3. Упаковка для переноса --------------------------------------------
SAVED_FILE=
if [ "$SAVE" = "1" ]; then
    if [ -z "$SAVE_PATH" ]; then
        # Имя из тега образа: ppe-tracker-api:data -> ppe-tracker-api-data
        SAVE_PATH="$(printf '%s' "$IMAGE_TO_SAVE" | tr ':/' '--')"
        [ "$GZIP" = "1" ] && SAVE_PATH="$SAVE_PATH.tar.gz" || SAVE_PATH="$SAVE_PATH.tar"
    fi

    step "Упаковываю $IMAGE_TO_SAVE в $SAVE_PATH"
    # docker save/gzip пишут в файл напрямую: образ ~570 МБ, через pipe
    # пришлось бы держать его в памяти оболочки
    if [ "$GZIP" = "1" ]; then
        docker save "$IMAGE_TO_SAVE" | gzip > "$SAVE_PATH" || die "упаковка не удалась"
    else
        docker save "$IMAGE_TO_SAVE" -o "$SAVE_PATH" || die "упаковка не удалась"
    fi

    size=$(wc -c < "$SAVE_PATH" | tr -d ' ')
    [ "$size" -gt 104857600 ] || die "файл подозрительно мал ($size байт)"
    ok "файл готов: $SAVE_PATH ($((size / 1048576)) МБ)"
    SAVED_FILE=$SAVE_PATH
fi

# --- 4. Итог --------------------------------------------------------------
step "Готово"
docker image ls --format '    {{.Repository}}:{{.Tag}}  {{.DiskUsage}}' 2>/dev/null \
    | grep -E "($PROD_IMAGE|$DATA_IMAGE)" || true

if [ -n "$SAVED_FILE" ]; then
    printf '\n'
    ok "файл для переноса: $SAVED_FILE"
    if [ "$GZIP" = "1" ]; then
        ok "распаковка на целевой машине: gzip -d $SAVED_FILE"
    fi
fi

# Инструкция печатается обычными if, а не $( ... && printf ... ): при set -e
# подстановка с ложным первым условием возвращает ненулевой код и может
# оборвать скрипт прямо на печати итога.
LOAD_PATH=
if [ -n "$SAVED_FILE" ]; then
    LOAD_PATH=$(printf '%s' "$SAVED_FILE" | sed 's/\.gz$//')
fi

printf '\n'
if [ "$WITH_DATA" = "1" ]; then
    printf 'Образ с данными: персональные сведения сотрудников внутри.\n'
    printf 'Не публикуйте его в registry и не передавайте без необходимости.\n'
else
    printf 'Образ чистый: схема и данные создаются при первом старте.\n'
fi
printf '\n'

printf 'Перенос на другую машину (Windows или Linux — формат один и тот же):\n\n'
if [ -n "$LOAD_PATH" ]; then
    printf '  1. скопировать файл: %s\n' "$SAVED_FILE"
else
    printf '  1. скопировать файл, созданный с флагом --save\n'
fi
printf '  2. загрузить образ:\n'
if [ -z "$LOAD_PATH" ]; then
    printf '       docker load -i ppe-tracker-api-*.tar\n'
elif [ "$GZIP" = "1" ]; then
    printf '       gzip -d %s\n' "$SAVED_FILE"
    printf '       docker load -i %s\n' "$LOAD_PATH"
else
    printf '       docker load -i %s\n' "$LOAD_PATH"
fi
printf '  3. проверить:  docker images %s\n\n' "$IMAGE_TO_SAVE"

printf 'Запуск на целевой машине — пустая база и авто-миграции:\n\n'
printf '  docker compose --env-file .env.prod -f docker-compose.prod.yml up -d db\n'
printf '  docker run -d --name ppe-api --network ppe-tracker_default \\\n'
printf '      -e SECRET_KEY=... -e POSTGRES_USER=... -e POSTGRES_PASSWORD=... \\\n'
printf '      -e POSTGRES_DB=... -e POSTGRES_HOST=db -e AUTO_MIGRATE=1 \\\n'
printf '      -p 127.0.0.1:8000:8000 %s\n' "$IMAGE_TO_SAVE"

if [ "$WITH_DATA" = "1" ]; then
    printf '\nПервый старт: миграции → дамп → uvicorn. Повторный старт дамп не повторяет.\n'
    printf 'Перезалить поверх живых данных: -e FORCE=1\n'
    printf 'Администратор приходит вместе с данными (хеш пароля из dev-базы).\n'
else
    printf '\nУчётку администратора завести один раз:\n'
    printf '  docker exec ppe-api python create_admin.py\n'
fi

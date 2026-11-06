#!/bin/sh
# make-data-image.sh — образ С ДАННЫМИ из dev-базы.
#
# Что делает: поднимает dev-базу, снимает с неё pg_dump, собирает
# ppe-tracker-api:prod + дамп = ppe-tracker-api:data (по умолчанию).
# На выходе — один образ, который при первом старте на пустой базе сам
# развернёт схему миграциями и зальёт данные. Сам он ничего не запускает.
#
# Запуск из корня клона в WSL:
#
#   chmod +x make-data-image.sh && ./make-data-image.sh
#   ./make-data-image.sh -t ppe-tracker-api:2026-11-06
#   ./make-data-image.sh -d /tmp/dump.sql     # накатить готовый дамп
#   ./make-data-image.sh --skip-dump          # только prod-образ, без данных
#
# Требования: docker compose v2 (на WSL Docker Desktop).
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
SKIP_DUMP=0
KEEP_DUMP=0

usage() {
    cat <<'EOF'
make-data-image.sh — собрать образ ppe-tracker-api с данными из dev-базы

Использование:
  ./make-data-image.sh [опции]

Опции:
  -t, --tag ОБРАЗ      тег итогового образа (по умолчанию ppe-tracker-api:data)
  -b, --base ОБРАЗ     тег базового прод-образа (по умолчанию ppe-tracker-api:prod)
  -d, --dump ФАЙЛ      взять готовый .sql вместо pg_dump из dev-базы
  -k, --keep-dump      не удалять временный каталог с дампом после сборки
      --skip-dump      собрать только базовый прод-образ, без данных
  -h, --help           эта справка

Что происходит:
  1. проверяются docker, демон, docker compose и файлы сборки;
  2. поднимается dev-база (docker compose up -d db), ждётся pg_isready;
  3. pg_dump из dev-базы: все таблицы, кроме данных alembic_version —
     схему развернёт alembic, его версия от dev-базы не должна подменяться;
  4. собирается ppe-tracker-api:prod, затем поверх — образ с дампом.

Внутри образа дамп лежит в /app/data/dump.sql и применяется при первом
старте на ПУСТОЙ базе; повторно не накатывается (маркер .dump-loaded).
Перезалить поверх живых данных: FORCE=1.
EOF
}

# --- Разбор аргументов ----------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--tag)       DATA_IMAGE=${2:?--tag требует значения}; shift 2 ;;
        -b|--base)      PROD_IMAGE=${2:?--base требует значения}; shift 2 ;;
        -d|--dump)      DUMP_FILE=${2:?--dump требует значения}; shift 2 ;;
        -k|--keep-dump) KEEP_DUMP=1; shift ;;
        --skip-dump)    SKIP_DUMP=1; shift ;;
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
docker compose version >/dev/null 2>&1 || die "нужен docker compose v2"

for f in dockerfile.prod dockerfile.data .dockerignore requirements.txt; do
    [ -f "$f" ] || die "нет $f: запускайте скрипт из корня клона"
done

# .dockerignore не должен выкидывать из контекста сборки нужное
if grep -qx 'data' .dockerignore 2>/dev/null; then
    die ".dockerignore содержит строку 'data' — собранный дамп не попадёт в образ"
fi

ok "docker: $(docker --version | sed 's/^Docker version //; s/,.*//')"
ok "compose: $(docker compose version --short 2>/dev/null || echo v2)"

if [ ! -f .env ]; then
    warn "нет .env — dev-база не стартует с пустыми POSTGRES_*."
    warn "Сделайте: cp .env.example .env и заполните SECRET_KEY и пароли."
fi

# --- 1. Dev-база ----------------------------------------------------------
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

# --- 2. Дамп --------------------------------------------------------------
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

if [ "$SKIP_DUMP" = "1" ]; then
    step "--skip-dump: только базовый прод-образ, без данных"
    docker build -f dockerfile.prod -t "$PROD_IMAGE" . || die "сборка $PROD_IMAGE не удалась"
    ok "готово: $PROD_IMAGE"
    exit 0
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ppe-data.XXXXXX")
mkdir -p "$TMP_DIR/data"

if [ -n "$DUMP_FILE" ]; then
    [ -f "$DUMP_FILE" ] || die "нет файла дампа: $DUMP_FILE"
    step "Беру готовый дамп $DUMP_FILE"
    cp "$DUMP_FILE" "$TMP_DIR/data/dump.sql"
else
    step "Снимаю pg_dump из dev-базы"

    # Содержимое alembic_version в дамп не берём (--exclude-table-data), но
    # саму таблицу и строку CREATE TABLE из pg_dump тоже не нужны: её создаёт
    # alembic. Убираем строку CREATE TABLE alembic_version, иначе
    # --single-transaction упрётся в "relation already exists".
    if ! docker compose -f "$COMPOSE_FILE" exec -T "$DEV_DB_SERVICE" \
            pg_dump -U "$dev_user" -d "$dev_db" \
            --no-owner --no-privileges \
            --clean --if-exists \
            --exclude-table-data=alembic_version \
            > "$TMP_DIR/dump.raw.sql"; then
        die "pg_dump не удался"
    fi

    dump_bytes=$(wc -c < "$TMP_DIR/dump.raw.sql" | tr -d ' ')
    [ "$dump_bytes" -gt 1024 ] || die "дамп подозрительно мал ($dump_bytes байт) — dev-база пуста?"

    # Вырезаем DDL и DROP по alembic_version: схему и версию ведёт alembic,
    # а данные этой таблицы уже исключены через --exclude-table-data.
    grep -v -E '^(DROP TABLE IF EXISTS public\.alembic_version|CREATE TABLE public\.alembic_version|ALTER TABLE ONLY public\.alembic_version|ALTER TABLE public\.alembic_version|COPY public\.alembic_version)' \
        "$TMP_DIR/dump.raw.sql" > "$TMP_DIR/data/dump.sql"
    rm -f "$TMP_DIR/dump.raw.sql"

    # Права: внутри контейнера читает app (uid 10001), скрипт может работать
    # под другим uid — выравниваем явно.
    chmod 0644 "$TMP_DIR/data/dump.sql"
    ok "дамп готов: $(wc -c < "$TMP_DIR/data/dump.sql" | tr -d ' ') байт"
fi

# --- 3. Сборка ------------------------------------------------------------
step "Собираю базовый образ $PROD_IMAGE"
docker build -f dockerfile.prod -t "$PROD_IMAGE" . || die "сборка $PROD_IMAGE не удалась"
ok "базовый образ готов"

step "Собираю образ с данными $DATA_IMAGE"
docker build -f dockerfile.data \
    --build-arg "BASE_IMAGE=$PROD_IMAGE" \
    -t "$DATA_IMAGE" "$TMP_DIR" \
    || die "сборка $DATA_IMAGE не удалась"
ok "образ с данными готов"

# --- 4. Итог --------------------------------------------------------------
step "Готово"
docker image ls --format '    {{.Repository}}:{{.Tag}}  {{.DiskUsage}}' 2>/dev/null \
    | grep -E "($PROD_IMAGE|$DATA_IMAGE)" || true

cat <<EOF

Дальше — запуск на ПУСТОЙ базе (порядок важен, см. PROJECT.md, «Прод-запуск»):

  docker compose --env-file .env.prod -f docker-compose.prod.yml up -d db
  docker run -d --name ppe-data \\
      --network ppe-tracker_default \\
      -e SECRET_KEY=... -e POSTGRES_USER=... -e POSTGRES_PASSWORD=... \\
      -e POSTGRES_DB=... -e POSTGRES_HOST=db -e AUTO_MIGRATE=1 \\
      -p 127.0.0.1:8000:8000 $DATA_IMAGE

Первый старт: миграции → дамп → uvicorn. Повторный старт дамп не повторяет.
Перезалить поверх живых данных: -e FORCE=1

Предупреждение: образ содержит персональные данные сотрудников.
Не публикуйте его в общий registry и не передавайте без необходимости.
EOF

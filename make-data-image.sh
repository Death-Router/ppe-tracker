#!/bin/sh
# make-data-image.sh — собрать образ PPE Tracker и упаковать его для переноса.
#
# По умолчанию собирается ЧИСТЫЙ образ: схема развернётся миграциями при
# первом старте, данных нет. С переносом данных из dev-базы — флаг --with-data.
# Флаг --save собирает архив .tar.gz для переноса: внутри обычный tar образа
# (docker save) и установщики install-ppe.sh / install-ppe.ps1 + INSTALL.txt —
# всё в корне архива, сжатие одно, на весь архив. На целевой машине достаточно
# распаковать и запустить установщик.
#
# Запуск из корня клона:
#
#   ./make-data-image.sh                          # чистый образ
#   ./make-data-image.sh --with-data              # + данные из dev-базы
#   ./make-data-image.sh --save                   # чистый + архив для переноса
#   ./make-data-image.sh --with-data --save       # то же с данными
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
GZIP_DEPRECATED=0
# Откуда брать фото сотрудников в режиме --with-data (в dev — bind-монт ./data)
PHOTO_SEED_DIR=${PHOTO_SEED_DIR:-data/photos}

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
  -s, --save [ФАЙЛ]    собрать архив .tar.gz (образ + установщики); без пути —
                       ppe-tracker-install-<tag>.tar.gz рядом со скриптом

Прочее:
  -h, --help           эта справка

Что происходит:
  чистый образ:  docker build -f dockerfile.prod  →  ppe-tracker-api:prod
  с данными:     плюс pg_dump dev-базы и слой с дампом  →  ...:data

Архив для переноса — один .tar.gz (сжатие не отключается), в корне лежат:
  ppe-tracker-api-<tag>.tar      образ, как его отдаёт docker save
  install-ppe.sh                 установщик для Linux / WSL / Git Bash
  install-ppe.ps1                установщик для Windows PowerShell
  INSTALL.txt                    три шага на месте
Сжатие одно — на весь архив целиком: вложенного .tar.gz нет, иначе образ
жался бы дважды.
На целевой машине: tar -xzf <архив> -C <папка>, затем запустить установщик —
образ он найдёт рядом с собой.

Ключ --gzip больше не нужен (архив всегда сжат); принимается для
совместимости старых команд и игнорируется.

Внутри образа с данными дамп лежит в /app/data/dump.sql и применяется при
первом старте на ПУСТОЙ базе; повторно не накатывается (маркер .dump-loaded).
Перезалить поверх живых данных: FORCE=1.

Фото сотрудников (data/photos) в дамп не входят, поэтому в режиме --with-data
они копируются в образ отдельно: /app/data/photo-seed, а entrypoint-data.sh
раскладывает их в том при старте, не перетирая уже загруженные файлы.
Источник можно переопределить: PHOTO_SEED_DIR=/путь/к/photos.

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
        --gzip)         GZIP_DEPRECATED=1; shift ;;
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

if [ "$GZIP_DEPRECATED" = "1" ]; then
    warn "--gzip больше не нужен: архив всегда .tar.gz (ключ проигнорирован)"
fi

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
if [ "$SAVE" = "1" ]; then
    # Архив собирается только из этих файлов: без них установка на целевой
    # машине превратится в ручное копирование команд из INSTALL.md
    for f in install-ppe.sh install-ppe.ps1; do
        [ -f "$f" ] || die "нет $f: он кладётся в корень архива --save"
    done
    for tool in tar gzip; do
        command -v "$tool" >/dev/null 2>&1 || die "нет $tool в PATH (нужен для --save)"
    done
fi

ok "docker: $(docker --version | sed 's/^Docker version //; s/,.*//')"
if [ "$WITH_DATA" = "1" ]; then
    ok "режим: с данными из dev-базы"
else
    ok "режим: чистый образ, без данных"
fi

# --- 1. Dev-база (только с данными) ---------------------------------------
TMP_DIR=
STAGE_DIR=
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
    # Стейджинг архива: копия образа ~200 МБ (сжатая). Без уборки она
    # остаётся в /tmp после каждого запуска.
    if [ -n "$STAGE_DIR" ] && [ -d "$STAGE_DIR" ]; then
        rm -rf "$STAGE_DIR"
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

    # Фото сотрудников в дампе нет: в БД только имена файлов, байты лежат на
    # томе (в dev — ./data/photos). Без копии на новой машине все карточки
    # показывают «нет фото», хотя строки employee_photos приехали.
    step "Кладу фото сотрудников в контекст сборки"
    mkdir -p "$TMP_DIR/photos"
    photo_count=0
    if [ -d "$PHOTO_SEED_DIR" ]; then
        for f in "$PHOTO_SEED_DIR"/*; do
            [ -f "$f" ] || continue
            cp "$f" "$TMP_DIR/photos/" || die "не удалось скопировать $f"
            photo_count=$((photo_count + 1))
        done
    fi
    chmod -R a+rX "$TMP_DIR/photos" 2>/dev/null || true
    if [ "$photo_count" -gt 0 ]; then
        ok "фото: $photo_count файл(ов) из $PHOTO_SEED_DIR"
    else
        warn "фото не найдено в $PHOTO_SEED_DIR — на новой машине карточки будут без снимков"
    fi

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

# --- 3. Архив для переноса ------------------------------------------------
# Один файл .tar.gz, в корне которого лежат и образ, и установщики: на
# целевой машине не нужно ничего искать и досочинять — распаковал и запустил.
SAVED_FILE=
if [ "$SAVE" = "1" ]; then
    # Имя образа без репозитория: ppe-tracker-api:data -> ppe-tracker-api-data,
    # тег отдельно — он идёт в имя архива (data / prod / свой).
    IMAGE_BASENAME=$(printf '%s' "$IMAGE_TO_SAVE" | tr ':/' '--')
    IMAGE_TAG=${IMAGE_TO_SAVE##*:}
    IMAGE_FILE="$IMAGE_BASENAME.tar"

    if [ -z "$SAVE_PATH" ]; then
        SAVE_PATH="ppe-tracker-install-$IMAGE_TAG.tar.gz"
    else
        # Путь задан вручную. Сжатие больше не опция, поэтому расширение
        # приводим к .tar.gz, а не молча пишем несжатый файл с чужим именем.
        case "$SAVE_PATH" in
            *.tar.gz) ;;
            *.tgz)    SAVE_PATH="${SAVE_PATH%.tgz}.tar.gz" ;;
            *.tar)    SAVE_PATH="$SAVE_PATH.gz" ;;
            *)        SAVE_PATH="$SAVE_PATH.tar.gz" ;;
        esac
    fi

    STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ppe-bundle.XXXXXX") \
        || die "не удалось создать временный каталог"

    step "Сохраняю образ $IMAGE_TO_SAVE"
    # Образ кладём как есть, tar-ом: сжимается он один раз — вместе со всем
    # архивом на шаге tar -czf. Вложенный .tar.gz дал бы двойное сжатие
    # (медленнее и без выигрыша в размере).
    docker save "$IMAGE_TO_SAVE" -o "$STAGE_DIR/$IMAGE_FILE" \
        || die "docker save не удался"
    tar -tf "$STAGE_DIR/$IMAGE_FILE" >/dev/null 2>&1 \
        || die "полученный $IMAGE_FILE не читается как tar"
    # docker save -o создаёт файл 0600: после распаковки архива root'ом в
    # /opt/ppe установщик под обычным пользователем не смог бы его прочитать
    chmod 0644 "$STAGE_DIR/$IMAGE_FILE"
    ok "образ сохранён: $IMAGE_FILE ($(( $(wc -c < "$STAGE_DIR/$IMAGE_FILE" | tr -d ' ') / 1048576 )) МБ)"

    step "Кладу в корень архива установщики"
    for f in install-ppe.sh install-ppe.ps1; do
        cp "$f" "$STAGE_DIR/$f" || die "не удалось скопировать $f"
    done
    # Бит +x в архиве: на Linux установщик запускают как ./install-ppe.sh
    chmod 0755 "$STAGE_DIR/install-ppe.sh"
    ok "install-ppe.sh, install-ppe.ps1"

    # Короткая памятка рядом с файлами: INSTALL.md в архив не входит, а
    # порядок действий из трёх шагов нужен именно здесь.
    cat > "$STAGE_DIR/INSTALL.txt" <<EOF
PPE Tracker — установка из архива
=================================

1. Распаковать архив (файлы появятся рядом):
     tar -xzf $(basename "$SAVE_PATH") -C <папка установки>
   На Windows 10/11 команда tar входит в систему.

2. Запустить установщик:
     Linux / WSL:  sh install-ppe.sh
     Windows:      powershell -NoProfile -ExecutionPolicy Bypass -File .\\install-ppe.ps1
   Образ ($IMAGE_FILE) установщик найдёт рядом с собой сам.

3. Открыть http://127.0.0.1:8000 и войти под учёткой, которую напечатает
   установщик (пароль генерируется на месте и лежит в .env установки).

Подробности, параметры и типовые отказы — INSTALL.md в репозитории.
EOF
    ok "INSTALL.txt"

    step "Собираю архив $SAVE_PATH"
    # Файлы перечисляем поимённо, без записи "./" для самого каталога: иначе
    # при распаковке в существующую папку tar применил бы к ней права
    # стейджинга (mktemp создаёт 0700) и неожиданно закрыл к ней доступ.
    tar -czf "$SAVE_PATH" -C "$STAGE_DIR" \
        install-ppe.sh install-ppe.ps1 INSTALL.txt "$IMAGE_FILE" \
        || die "tar не удался"

    # Проверка содержимого: пустой или частичный архив обнаружится здесь,
    # а не на целевой машине.
    tar -tzf "$SAVE_PATH" >/dev/null 2>&1 || die "архив $SAVE_PATH не читается"
    for need in install-ppe.sh install-ppe.ps1 INSTALL.txt "$IMAGE_FILE"; do
        tar -tzf "$SAVE_PATH" | grep -qx "$need" \
            || die "в архиве нет $need"
    done
    ok "в архиве: $IMAGE_FILE, install-ppe.sh, install-ppe.ps1, INSTALL.txt"

    size=$(wc -c < "$SAVE_PATH" | tr -d ' ')
    [ "$size" -gt 104857600 ] || die "архив подозрительно мал ($size байт)"
    ok "архив готов: $SAVE_PATH ($((size / 1048576)) МБ)"
    SAVED_FILE=$SAVE_PATH
fi

# --- 4. Итог --------------------------------------------------------------
step "Готово"
docker image ls --format '    {{.Repository}}:{{.Tag}}  {{.DiskUsage}}' 2>/dev/null \
    | grep -E "($PROD_IMAGE|$DATA_IMAGE)" || true

if [ -n "$SAVED_FILE" ]; then
    printf '\n'
    ok "архив для переноса: $SAVED_FILE"
    ok "внутри: образ .tar.gz, install-ppe.sh, install-ppe.ps1, INSTALL.txt"
fi

printf '\n'
if [ "$WITH_DATA" = "1" ]; then
    printf 'Образ с данными: персональные сведения сотрудников внутри.\n'
    printf 'Не публикуйте его в registry и не передавайте без необходимости.\n'
else
    printf 'Образ чистый: схема и данные создаются при первом старте.\n'
fi
printf '\n'

if [ -n "$SAVED_FILE" ]; then
    printf 'Перенос на другую машину (Windows или Linux — формат один и тот же):\n\n'
    printf '  1. скопировать архив: %s\n' "$SAVED_FILE"
    printf '  2. распаковать:       tar -xzf %s -C <папка установки>\n' \
        "$(basename "$SAVED_FILE")"
    printf '  3. запустить установщик из этой папки:\n'
    printf '       Linux / WSL:  sh install-ppe.sh\n'
    printf '       Windows:      powershell -NoProfile -ExecutionPolicy Bypass -File .\\install-ppe.ps1\n'
    printf '     Образ ищется рядом со скриптом, параметры не нужны.\n'
    printf '\n'
else
    printf 'Файл для переноса не создавался (флаг --save не указан).\n'
    printf 'Только образ: docker save %s -o образ.tar\n\n' "$IMAGE_TO_SAVE"
fi

printf 'То же самое вручную, без установщика (пустая база и авто-миграции):\n\n'
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

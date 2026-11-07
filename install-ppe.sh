#!/bin/sh
# install-ppe.sh — автоматическая установка PPE Tracker из образа.
#
# Загружает образ из .tar, создаёт каталог установки, генерирует .env и
# docker-compose.yml, поднимает базу и приложение, ждёт готовности и
# заводит администратора (для чистого образа).
#
# Запуск — из любого места, от обычного пользователя (Docker должен работать):
#
#   sh install-ppe.sh                                  # образ с данными из ./ppe-tracker-api-data.tar
#   sh install-ppe.sh ppe-tracker-api-data.tar         # указать файл
#   sh install-ppe.sh clean.tar --clean                # чистый образ, завести админа
#   sh install-ppe.sh data.tar -d /opt/ppe             # другой каталог установки
#
# Идемпотентность: повторный запуск не трогает данные. Если приложение уже
# установлено в каталоге, скрипт спросит, прежде чем перезаписывать .env.
#
# Скрипт — POSIX sh. Работает в WSL/Ubuntu (bash или dash) и в Git Bash на
# Windows. Для Windows без Git Bash есть install-ppe.ps1.

set -eu

# --- Значения по умолчанию -----------------------------------------------
INSTALL_DIR=${INSTALL_DIR:-/opt/ppe}
IMAGE=
CLEAN=0
PORT=${PORT:-8000}
ADMIN_USER=${ADMIN_USER:-admin}
ADMIN_PASS=
FORCE=0

usage() {
    cat <<'EOF'
install-ppe.sh — установка PPE Tracker из образа

Использование:
  sh install-ppe.sh [ФАЙЛ.tar] [опции]

Аргументы:
  ФАЙЛ.tar             файл образа (по умолчанию ищется ppe-tracker-api-data.tar
                       рядом со скриптом). Если архив .tar.gz — распакуется.

Опции:
  -d, --dir ПАПКА      каталог установки (по умолчанию /opt/ppe)
  -p, --port ПОРТ      порт приложения на 127.0.0.1 (по умолчанию 8000)
      --clean          образ без данных: завести администратора после старта
      --admin-login Л   логин администратора (по умолчанию admin)
      --admin-pass П   пароль администратора (по умолчанию сгенерируется)
      --force          перезаписать .env и compose, не спрашивая
  -h, --help           эта справка

Что делает:
  1. проверяет docker и файл образа;
  2. docker load -i ФАЙЛ;
  3. создаёт каталог, .env (SECRET_KEY и пароли генерируются) и
     docker-compose.yml;
  4. docker compose up -d, ждёт /healthz;
  5. для --clean: docker exec ... python create_admin.py;
  6. печатает адрес, логин и пароль.

Данные хранятся в томе ppe_pgdata и при перезапуске не теряются.
EOF
}

# --- Разбор аргументов ----------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir)        INSTALL_DIR=${2:?--dir требует значения}; shift 2 ;;
        -p|--port)       PORT=${2:?--port требует значения}; shift 2 ;;
        --clean)         CLEAN=1; shift ;;
        --admin-login)   ADMIN_USER=${2:?--admin-login требует значения}; shift 2 ;;
        --admin-pass)    ADMIN_PASS=${2:?--admin-pass требует значения}; shift 2 ;;
        --force)         FORCE=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              echo "Неизвестная опция: $1 (см. --help)" >&2; exit 2 ;;
        *)               IMAGE=$1; shift ;;
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

# Генератор секретов. python3 есть почти везде, но не гарантирован —
# тогда берём /dev/urandom (Linux/WSL). На Git Bash он есть как /dev/urandom.
gen_secret() {
    n=${1:-48}
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import secrets,sys; sys.stdout.write(secrets.token_urlsafe($n))"
    elif [ -r /dev/urandom ]; then
        # python3 нет: берём символы из /dev/urandom. tr оставляет только
        # URL-безопасный алфавит, head -c обрезает до нужной длины.
        LC_ALL=C tr -dc 'A-Za-z0-9_-' < /dev/urandom | head -c "$n" || true
    else
        die "нет python3 и нет /dev/urandom: задайте пароли через --admin-pass"
    fi
}

# --- Окружение ------------------------------------------------------------
step "Проверяю окружение"

command -v docker >/dev/null 2>&1 || die "нет docker в PATH — установите Docker Desktop (Windows) или Docker Engine (Linux)"
docker info >/dev/null 2>&1 || die "демон Docker не отвечает — запустите Docker Desktop"
docker compose version >/dev/null 2>&1 || die "нужен docker compose v2"

ok "docker: $(docker --version | sed 's/^Docker version //; s/,.*//')"
ok "compose: $(docker compose version --short 2>/dev/null || echo v2)"

# --- Файл образа ----------------------------------------------------------
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ -z "$IMAGE" ]; then
    for cand in ppe-tracker-api-data.tar ppe-tracker-api-prod.tar \
                ppe-tracker-api-data.tar.gz ppe-tracker-api-prod.tar.gz; do
        if [ -f "$SCRIPT_DIR/$cand" ]; then
            IMAGE=$SCRIPT_DIR/$cand
            break
        fi
    done
fi
[ -n "$IMAGE" ] || die "не найден файл образа. Укажите его: sh install-ppe.sh ppe-tracker-api-data.tar"
[ -f "$IMAGE" ] || die "нет файла: $IMAGE"

case "$IMAGE" in
    *.tar.gz)
        step "Распаковываю $IMAGE"
        gunzip -kf "$IMAGE" || die "не удалось распаковать $IMAGE"
        IMAGE=${IMAGE%.gz}
        ok "получен $IMAGE"
        ;;
esac

ok "образ: $IMAGE"

# --- Каталог установки ----------------------------------------------------
step "Каталог установки: $INSTALL_DIR"

if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
    if [ "$(id -u)" = "0" ]; then
        # Работаем от root (например, sudo sh install-ppe.sh)
        ok "создан $INSTALL_DIR"
    elif [ -w "$INSTALL_DIR" ]; then
        ok "создан $INSTALL_DIR"
    else
        # Каталог создан через sudo — вернём владельца себе, иначе compose
        # не сможет писать рядом с файлами
        sudo chown -R "$(id -u):$(id -g)" "$INSTALL_DIR" 2>/dev/null || true
        ok "создан $INSTALL_DIR (владелец: $(id -un))"
    fi
else
    ok "каталог существует"
fi

[ -w "$INSTALL_DIR" ] || die "нет прав на запись в $INSTALL_DIR. Запустите с sudo или укажите -d ~/ppe"

# --- Загрузка образа ------------------------------------------------------
step "Загружаю образ"
# Тег берём из вывода load, а не из `docker image ls`: на машине может уже
# лежать другой ppe-tracker-api:* (например, :data от прошлой сборки), и
# первая строка списка — не обязательно только что загруженный образ.
LOAD_OUT=$(docker load -i "$IMAGE" 2>&1) || {
    printf '%s\n' "$LOAD_OUT" >&2
    die "docker load не удался"
}
ok "образ загружен"

IMAGE_NAME=$(printf '%s\n' "$LOAD_OUT" \
    | sed -n 's/^Loaded image: //p' \
    | grep -E '^ppe-tracker-api:' | head -1)
if [ -z "$IMAGE_NAME" ]; then
    # docker load без тегов печатает "Loaded image ID: sha256:..." — тогда
    # остаётся поиск по списку образов
    IMAGE_NAME=$(docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | grep -E '^ppe-tracker-api:' | head -1)
fi
[ -n "$IMAGE_NAME" ] || die "в загруженном архиве нет образа ppe-tracker-api"
ok "тег: $IMAGE_NAME"

# .data — образ с дампом; .prod — чистый
case "$IMAGE_NAME" in
    *:data) [ "$CLEAN" = "1" ] && warn "загружен образ с данными, но указан --clean" ;;
    *:prod) [ "$CLEAN" = "0" ] && { warn "загружен чистый образ, а флаг --clean не задан"; CLEAN=1; } ;;
esac

# --- .env и compose -------------------------------------------------------
ENV_FILE=$INSTALL_DIR/.env
COMPOSE_FILE=$INSTALL_DIR/docker-compose.yml

if [ -f "$ENV_FILE" ] && [ "$FORCE" != "1" ]; then
    printf '%s    %s%s\n' "$C_WARN" "$ENV_FILE уже существует. Перезаписать? [y/N] " "$C_OFF"
    read -r answer || answer=n
    case "$answer" in
        y|Y|yes|Yes) ;;
        *) warn "оставляю существующий .env (секреты не меняются)"; KEEP_ENV=1 ;;
    esac
fi
KEEP_ENV=${KEEP_ENV:-0}

# Тома compose привязаны к имени проекта, а оно по умолчанию — имя каталога.
# Две папки с именем ppe делят один проект и одни тома: новый .env с новым
# паролем встречается с томом прежней установки, и база отвечает
# «password authentication failed for user». Предупреждаем заранее.
existing_volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E '_ppe_(pgdata|photos)$' || true)
if [ -n "$existing_volumes" ]; then
    warn "найдены существующие тома: $(printf '%s' "$existing_volumes" | tr '\n' ' ')"
    warn "если это прежняя установка с другим паролем, база не пустит приложение."
    warn "варианты: сохранить старый .env (ответить n) или пересоздать базу: docker compose -f <compose> down -v"
fi

if [ "$KEEP_ENV" = "0" ]; then
    step "Генерирую секреты и .env"
    [ -n "$ADMIN_PASS" ] || ADMIN_PASS=$(gen_secret 18)
    SECRET_KEY=$(gen_secret 48)
    PG_PASS=$(gen_secret 24)
    [ -n "$SECRET_KEY" ] || die "не удалось сгенерировать SECRET_KEY"
    [ -n "$PG_PASS" ] || die "не удалось сгенерировать пароль БД"

    # umask перед созданием: файл с секретами не должен быть доступен всем
    (umask 077
     cat > "$ENV_FILE" <<EOF
# PPE Tracker — окружение установки. Создано install-ppe.sh $(date +%Y-%m-%d).
# Здесь секреты: не добавляйте файл в git и не пересылайте его.

SECRET_KEY=$SECRET_KEY
ENVIRONMENT=production
# true — только за HTTPS на reverse-proxy. Для локального http оставьте false.
SESSION_COOKIE_SECURE=false
# Применять миграции при старте: нужно при первом старте и после обновления.
AUTO_MIGRATE=1

POSTGRES_USER=ppe
POSTGRES_PASSWORD=$PG_PASS
POSTGRES_DB=ppe_db
# Хост базы внутри compose. Нужен образу с данными: entrypoint-data.sh
# подключается psql по этим переменным, а не через settings приложения.
POSTGRES_HOST=db
POSTGRES_PORT=5432

ADMIN_USERNAME=$ADMIN_USER
ADMIN_PASSWORD=$ADMIN_PASS
EOF
    ) || die "не удалось записать $ENV_FILE"
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    ok "$ENV_FILE создан (права 600)"
else
    # Секреты уже есть — читаем, что нужно для вывода и для create_admin
    SECRET_KEY=$(sed -n 's/^SECRET_KEY=//p' "$ENV_FILE" | tail -1)
    ADMIN_USER=$(sed -n 's/^ADMIN_USERNAME=//p' "$ENV_FILE" | tail -1)
    ADMIN_PASS=$(sed -n 's/^ADMIN_PASSWORD=//p' "$ENV_FILE" | tail -1)
    [ -n "$SECRET_KEY" ] || die "в $ENV_FILE нет SECRET_KEY"
    ok "использую существующий $ENV_FILE"
fi

step "Пишу docker-compose.yml"
cat > "$COMPOSE_FILE" <<EOF
# Создано install-ppe.sh. Правьте осторожно: при повторной установке с
# --force файл перезаписывается.
services:
  api:
    image: $IMAGE_NAME
    container_name: ppe-api
    restart: unless-stopped
    env_file: .env
    ports:
      # Только локально: наружу — через reverse-proxy с HTTPS
      - "127.0.0.1:${PORT}:8000"
    volumes:
      # Фото сотрудников: файлы на томе, в БД только имена. Без тома фото
      # лежат в слое контейнера и пропадают при первом же обновлении образа.
      - ppe_photos:/app/data/photos
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=4).status == 200 else 1)"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

  db:
    image: postgres:16-alpine
    container_name: ppe-db
    restart: unless-stopped
    environment:
      # :? — compose остановится с понятным текстом, если .env неполный,
      # вместо тихого пустого POSTGRES_USER (на этом уже спотыкались)
      POSTGRES_USER: \${POSTGRES_USER:?задайте POSTGRES_USER в .env}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:?задайте POSTGRES_PASSWORD в .env}
      POSTGRES_DB: \${POSTGRES_DB:?задайте POSTGRES_DB в .env}
    volumes:
      - ppe_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  ppe_pgdata:
  # Фото сотрудников: персональные данные, бэкапятся отдельно от дампа
  ppe_photos:
EOF
ok "$COMPOSE_FILE создан"

# Проверка сразу, а не на docker compose up: битый шаблон (например, пустой
# порт из-за подстановки переменной) всплывает уже при up и ругается невнятно
# ("no port specified: 127.0.0.1:<empty>"). config называет причину.
if ! compose_check=$(docker compose -f "$COMPOSE_FILE" config -q 2>&1); then
    printf '%s\n' "$compose_check" >&2
    die "docker-compose.yml некорректен — см. сообщение выше"
fi
ok "$COMPOSE_FILE проверен (docker compose config)"

# --- Запуск ---------------------------------------------------------------
step "Поднимаю контейнеры"
cd "$INSTALL_DIR"
docker compose up -d || die "docker compose up не удался. Логи: docker compose -f $COMPOSE_FILE logs"

step "Жду готовности приложения"
attempt=1
ready=0
while [ "$attempt" -le 60 ]; do
    code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/healthz" 2>/dev/null || echo 000)
    if [ "$code" = "200" ]; then
        ready=1
        break
    fi
    attempt=$((attempt + 1))
    sleep 2
done

if [ "$ready" != "1" ]; then
    # Две разные беды: приложение не работает ИЛИ работает, а порт с хоста не
    # отвечает (проброс портов, занятый порт). Изнутри контейнера приложение
    # всегда на 127.0.0.1:8000.
    if docker exec ppe-api python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=4).status == 200 else 1)" >/dev/null 2>&1; then
        warn "приложение внутри контейнера отвечает, а http://127.0.0.1:$PORT/healthz — нет"
        warn "порт не пробросился с хоста: проверьте занятость порта и docker run -p"
        ok "образ загружен, контейнеры подняты — установка считается выполненной"
    else
        warn "приложение не ответило за 120 с (последний код: $code)"
        step "Состояние контейнеров"
        docker compose ps || true
        step "Последние строки лога api"
        log_tail=$(docker compose logs --tail 40 api 2>&1 || true)
        printf '%s\n' "$log_tail"
        warn "полный лог: docker compose -f $COMPOSE_FILE logs -f api"

        # Самая частая причина: том базы остался от прежней установки с другим
        # паролем (проект compose называется по имени каталога). Подсказываем
        # лечение; данные не теряются — образ с данными зальёт дамп заново.
        if printf '%s' "$log_tail" | grep -q 'password authentication failed'; then
            step "Причина: пароль базы не совпадает с томом"
            warn "том базы создан раньше, с другим POSTGRES_PASSWORD."
            warn "лечение (данные базы и фото будут созданы заново из образа):"
            warn "  docker compose -f $COMPOSE_FILE down -v"
            warn "  затем запустить установщик ещё раз"
            warn "или вернуть прежний пароль в .env (POSTGRES_PASSWORD) и повторить"
        fi
        die "установка не завершена: приложение не поднялось (причина выше)"
    fi
fi
ok "приложение отвечает (healthz 200)"

# --- Администратор --------------------------------------------------------
if [ "$CLEAN" = "1" ]; then
    step "Завожу администратора"
    # create_admin.py читает ADMIN_* из окружения контейнера (env_file),
    # поэтому ничего передавать не нужно. Скрипт идемпотентен.
    admin_out=$(docker exec ppe-api python create_admin.py 2>&1 || true)
    case "$admin_out" in
        *"уже существует"*) warn "пользователь $ADMIN_USER уже был — пароль не менялся" ;;
        *) ok "администратор $ADMIN_USER создан" ;;
    esac
else
    ok "образ с данными: учётка администратора пришла вместе с данными"
fi

# --- Итог -----------------------------------------------------------------
printf '\n'
step "Установка завершена"
printf '\n'
printf '  Адрес:      http://127.0.0.1:%s\n' "$PORT"
printf '  Логин:      %s\n' "${ADMIN_USER:-см. .env}"
if [ "$CLEAN" = "1" ] && [ -n "${ADMIN_PASS:-}" ]; then
    printf '  Пароль:     %s\n' "$ADMIN_PASS"
elif [ "$CLEAN" = "1" ]; then
    printf '  Пароль:     из %s (ADMIN_PASSWORD)\n' "$ENV_FILE"
else
    printf '  Пароль:     пароль администратора из dev-базы\n'
fi
printf '  Каталог:    %s\n' "$INSTALL_DIR"
printf '  .env:       %s  (секреты — не пересылать)\n' "$ENV_FILE"
printf '\n'
printf 'Управление:\n'
printf '  cd %s\n' "$INSTALL_DIR"
printf '  docker compose ps            # состояние\n'
printf '  docker compose logs -f api   # логи\n'
printf '  docker compose restart api   # перезапуск\n'
printf '  docker compose down          # остановить (данные сохранятся)\n'
printf '\n'
printf 'Резервная копия базы:\n'
# shellcheck disable=SC2016  # печатаем инструкцию: $(date) должен раскрыться
# у пользователя при выполнении, а не сейчас
printf '  docker exec ppe-db sh -c %s > backup_$(date +%%F).sql\n' \
    "'pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --no-owner'"
printf '\n'
printf 'Резервная копия фото (отдельно от дампа: файлы лежат на томе):\n'
# shellcheck disable=SC2016  # $(date) должен раскрыться у пользователя
printf '  docker exec ppe-api tar czf - -C /app/data/photos . > photos_$(date +%%F).tar.gz\n'

if [ "$CLEAN" != "1" ]; then
    warn "в образе персональные данные сотрудников — не публикуйте образ в registry"
fi

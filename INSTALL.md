# Установка PPE Tracker из образа

Инструкция для того, кто ставит приложение на новую машину: создать образ
на машине с исходниками и запустить его на Windows или Linux.

Два пути:

- **A. Перенос готового образа** — файл `.tar`, ничего не нужно кроме Docker.
  Работает без интернета и без исходников. **Основной путь.**
- **B. Сборка на целевой машине** — копируется репозиторий, образ собирается
  `docker build`. Нужен интернет (скачать `python:3.11-slim` и зависимости).

Что попадает в образ и как устроен запуск — в `PROJECT.md`, разделы
«Прод-запуск» и «Образ с данными».

---

## 1. Что понадобится

| | Windows | Linux |
|---|---|---|
| Docker | Docker Desktop (WSL2) | Docker Engine + плагин `docker compose` |
| Проверка | `docker version` | `docker version` |
| Свободное место | ~2 ГБ под образ и БД | ~2 ГБ |
| Порты | 127.0.0.1:8000 | 127.0.0.1:8000 |

Если `docker version` пишет `Cannot connect to the Docker daemon` —
Docker не запущен. На Windows запустите Docker Desktop и дождитесь
«Engine running».

---

## 2. Создание образа (на машине с исходниками)

Все команды — из корня клона репозитория. Есть два варианта образа.

### 2.1 Чистый — без данных (по умолчанию)

Схема развернётся миграциями при первом старте, справочники будут пустыми,
администратора заводит человек при установке.

```bash
./make-data-image.sh --save
```

Результат: `ppe-tracker-api:prod` и файл `ppe-tracker-api-prod.tar` (~570 МБ).

### 2.2 С данными из dev-базы

Копируются сотрудники, СИЗ, нормы, выдачи и **учётка администратора**.
Скрипт поднимет dev-базу, снимет `pg_dump` и соберёт образ с дампом.

```bash
./make-data-image.sh --with-data --save
```

Результат: `ppe-tracker-api:data` и файл `ppe-tracker-api-data.tar`.

Со сжатием — файл примерно втрое меньше (`.tar.gz`):

```bash
./make-data-image.sh --with-data --save --gzip
```

⚠️ **Образ с данными содержит персональные сведения сотрудников.** Не
публикуйте его в общий registry и передавайте только по защищённому каналу.

### 2.3 Если скрипт не запускается

```bash
chmod +x make-data-image.sh
./make-data-image.sh --save
```

`Permission denied` после копирования файла — обычное дело: бит исполнения
переживает не каждый перенос. Альтернатива: `sh make-data-image.sh --save`.

### 2.4 Без скрипта

Эквивалент чистого образа:

```bash
docker build -f dockerfile.prod -t ppe-tracker-api:prod .
docker save ppe-tracker-api:prod -o ppe-tracker-api-prod.tar
```

---

## 3. Перенос файла

Формат `docker save` одинаковый на Windows и Linux — файл переносится как
есть: флешка, сетевой диск, `scp`. Сжимать для переноса не обязательно.

```bash
# Linux → Linux, если есть ssh
scp ppe-tracker-api-prod.tar user@server:/opt/ppe/
```

Если файл сжат, на целевой машине сначала распаковать:

```bash
gzip -d ppe-tracker-api-data.tar.gz        # станет .tar
```

На Windows: `.gz` открывается архиватором, результат — файл `.tar`.

---

## 4. Установка на Windows (Docker Desktop)

### 4.1 Загрузить образ

В PowerShell:

```powershell
docker load -i C:\путь\ppe-tracker-api-prod.tar
docker images ppe-tracker-api
```

Должна быть строка `ppe-tracker-api  prod`.

### 4.2 Создать каталог и файл окружения

```powershell
mkdir C:\ppe
cd C:\ppe
```

Создайте `C:\ppe\.env` с содержимым (значения — свои):

```ini
SECRET_KEY=<48+ символов, см. ниже>
ENVIRONMENT=production
SESSION_COOKIE_SECURE=false
AUTO_MIGRATE=1
POSTGRES_USER=ppe
POSTGRES_PASSWORD=<пароль>
POSTGRES_DB=ppe_db
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<пароль администратора>
```

`SECRET_KEY` генерируется так:

```powershell
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

`SESSION_COOKIE_SECURE=false` — для локального http. При установке за
reverse-proxy с HTTPS поставьте `true`, иначе вход не сработает.

### 4.3 Создать compose-файл

`C:\ppe\docker-compose.yml`:

```yaml
services:
  api:
    image: ppe-tracker-api:prod
    container_name: ppe-api
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16-alpine
    container_name: ppe-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:?задайте POSTGRES_USER в .env}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?задайте POSTGRES_PASSWORD в .env}
      POSTGRES_DB: ${POSTGRES_DB:?задайте POSTGRES_DB в .env}
    volumes:
      - ppe_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  ppe_pgdata:
```

Образ с данными называется `ppe-tracker-api:data` — замените `image:` на него,
если переносите с данными.

### 4.4 Запустить

```powershell
cd C:\ppe
docker compose up -d
docker compose ps
```

Ожидается: `ppe-db` — `healthy`, `ppe-api` — `Up (healthy)`. Миграции
применяются на первом старте, это занимает 10–20 секунд.

Проверка:

```powershell
curl.exe -s -o NUL -w "healthz=%{http_code}`n" http://127.0.0.1:8000/healthz
```

`healthz=200` — приложение готово.

### 4.5 Администратор (только для чистого образа)

Если образ без данных, завести учётку один раз — логин и пароль из `.env`:

```powershell
docker exec ppe-api python create_admin.py
```

Для образа с данными пропустите: учётка приходит из dev-базы.

### 4.6 Открыть

<http://127.0.0.1:8000>

### 4.7 Или одной командой

`install-ppe.ps1` делает всё из разделов 4.1–4.5: загружает образ, создаёт
каталог, генерирует `.env`, пишет `docker-compose.yml`, поднимает контейнеры
и заводит администратора.

Политика выполнения в Windows запрещает `.ps1` по двойному клику, поэтому
запуск — из PowerShell с обходом политики (тот же приём, что в
`push-ppe.cmd`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-ppe.ps1 `
    -Image .\ppe-tracker-api-data.tar -Dir C:\ppe
```

Для чистого образа — добавить `-Clean`, тогда скрипт ещё и заведёт
администратора:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-ppe.ps1 `
    -Image .\ppe-tracker-api-prod.tar -Clean -AdminPass 'СложныйПароль1'
```

| Параметр | По умолчанию | Назначение |
|---|---|---|
| `-Image` | ищет `.tar` рядом со скриптом | файл образа |
| `-Dir` | `C:\ppe` | каталог установки |
| `-Port` | `8000` | порт на `127.0.0.1` |
| `-Clean` | — | образ без данных: завести администратора |
| `-AdminLogin` / `-AdminPass` | `admin` / сгенерирован | учётка |
| `-Force` | — | перезаписать `.env` без вопроса |

Скрипт идемпотентен: повторный запуск не трогает данные, а существующий
`.env` перезаписывает только после подтверждения.

---

## 5. Установка на Linux

Всё то же самое, отличия в путях и правах.

### 5.0 Или одной командой

`install-ppe.sh` — то же самое для POSIX-шелла (WSL, Ubuntu, любой Linux):

```bash
sh install-ppe.sh ppe-tracker-api-data.tar -d /opt/ppe
sh install-ppe.sh ppe-tracker-api-prod.tar -d /opt/ppe --clean
```

Параметры: `-d` каталог, `-p` порт, `--clean`, `--admin-login`,
`--admin-pass`, `--force`. Скрипт работает от обычного пользователя;
`sudo` сам вызывается только чтобы создать каталог, если его нет.

### 5.1 Загрузить образ

```bash
docker load -i /opt/ppe/ppe-tracker-api-prod.tar
docker images ppe-tracker-api
```

### 5.2 Каталог и файлы

```bash
sudo mkdir -p /opt/ppe && sudo chown "$USER" /opt/ppe
cd /opt/ppe
```

`.env` — тот же, что в 4.2. Создать:

```bash
cat > .env <<EOF
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(48))")
ENVIRONMENT=production
SESSION_COOKIE_SECURE=false
AUTO_MIGRATE=1
POSTGRES_USER=ppe
POSTGRES_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")
POSTGRES_DB=ppe_db
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(12))")
EOF
chmod 600 .env
```

⚠️ Запишите сгенерированные пароли: `POSTGRES_PASSWORD` понадобится только
внутри compose, а `ADMIN_PASSWORD` — для входа.

`docker-compose.yml` — как в 4.3 (тот же файл, формат один).

### 5.3 Запустить

```bash
docker compose up -d
docker compose ps
curl -s -o /dev/null -w "healthz=%{http_code}\n" http://127.0.0.1:8000/healthz
```

### 5.4 Публикация в сеть

По умолчанию приложение слушает только `127.0.0.1` — снаружи недоступно,
это намеренно. Наружу его открывает reverse-proxy с HTTPS:

```nginx
server {
    listen 443 ssl;
    server_name ppe.example.ru;

    ssl_certificate     /etc/ssl/ppe.crt;
    ssl_certificate_key /etc/ssl/ppe.key;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

С HTTPS обязательно поставьте `SESSION_COOKIE_SECURE=true` в `.env` и
перезапустите: `docker compose up -d --force-recreate`.

WebSocket `/ws/*` работает через `proxy_pass` без дополнительных настроек.

---

## 6. Проверка, что всё встало

| Что | Команда | Ожидание |
|---|---|---|
| приложение живо | `curl 127.0.0.1:8000/healthz` | `{"status":"ok"}` |
| схема на голове | `docker exec ppe-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select version_num from alembic_version;"'` | одна строка; та же ревизия, что `docker exec ppe-api alembic heads` (без `(head)`) |
| данные (если образ с данными) | `docker exec ppe-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from employees;"'` | число > 0 |
| вход | браузер | страница входа |
| схема API закрыта | `curl -o /dev/null -w "%{http_code}" 127.0.0.1:8000/docs` | `404` |

Логин и база в командах не зашиты: `psql` внутри контейнера берёт
`POSTGRES_USER`/`POSTGRES_DB` из своего окружения (их задаёт `.env`).
Ревизию головы сверяйте сравнением двух выводов, а не с числом из этой
инструкции — при новой миграции конкретный id устареет.

`/docs` = 404 — это правильно: при `ENVIRONMENT=production` схема API
закрыта намеренно.

---

## 7. Если что-то не так

**`dependency failed to start: container ppe-db is unhealthy`**

Пустые `POSTGRES_*`. Compose подставляет `${...}` из `.env`, а `env_file`
у `api` на `db` не действует. Проверьте, что `.env` лежит рядом с
`docker-compose.yml` и в нём заполнены `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_DB`.

**`exec /usr/local/bin/entrypoint.sh: no such file or directory`**

CRLF в скрипте внутри образа. Образ собран из Windows-клона с
`core.autocrlf=true`. Лечится в репозитории (`.gitattributes` + `sed` в
`dockerfile.prod`) и уже исправлено; если видите это — образ старый,
пересоберите.

**`SECRET_KEY не задан` или `SECRET_KEY слишком короткий`**

Ключ пуст или короче 32 символов. Приложение не стартует осознанно, без
тихого дефолта.

**Вход не срабатывает, страница обновляется молча**

`SESSION_COOKIE_SECURE=true` при http. Поставьте `false` (или включите HTTPS).

**Дамп не применился, `size_group_id ... is not present`**

Заливка дампа в образе с данными требует `SET session_replication_role`,
а пользователь БД не суперпользователь. В `postgres:16-alpine` пользователь
из `POSTGRES_USER` — суперпользователь; если база внешняя, дайте права.

**Повторно залить данные в непустую базу**

Без `FORCE=1` контейнер с данными на непустой базе данные не трогает: пишет в
лог «данные уже есть» и просто запускает приложение.

```bash
docker run --rm --network <сеть> --env-file .env -e FORCE=1 \
    -e AUTO_MIGRATE=1 ppe-tracker-api:data
```

`--env-file .env` обязателен: без `SECRET_KEY` и `POSTGRES_*` контейнер
упадёт на старте ещё до заливки. `FORCE=1` **удалит текущие данные** перед
заливкой — делайте резервную копию (раздел 9).

---

## 8. Обновление на новую версию

```bash
# на машине с исходниками
./make-data-image.sh --save              # новый файл .tar

# на целевой
docker load -i ppe-tracker-api-prod.tar
docker compose up -d                     # пересоздаст api на новом образе
```

Миграции применятся автоматически при старте (`AUTO_MIGRATE=1`). Данные
остаются в томе `ppe_pgdata` — обновление образа их не трогает.

---

## 9. Резервное копирование

Только база, без образа (логин и имя базы берутся из окружения контейнера):

```bash
docker exec ppe-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner' \
    > backup_$(date +%F).sql
```

Восстановление:

```bash
docker exec -i ppe-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    < backup_2026-11-06.sql
```

Файлы резервных копий содержат персональные данные — храните соответственно.

---

## 10. Удаление

```bash
docker compose down            # остановить, данные в томе сохранятся
docker compose down -v         # + удалить том с базой (НЕОБРАТИМО)
docker image rm ppe-tracker-api:prod
```

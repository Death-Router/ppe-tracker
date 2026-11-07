<#
.SYNOPSIS
    Автоматическая установка PPE Tracker из образа на Windows.

.DESCRIPTION
    Загружает образ из .tar, создаёт каталог установки, генерирует .env и
    docker-compose.yml, поднимает базу и приложение, ждёт готовности и
    заводит администратора (для чистого образа).

    Требуется Docker Desktop (Windows-контейнеры не нужны — образ Linux,
    Docker Desktop запускает их через WSL2).

    Параметры совпадают с install-ppe.sh: Image, Dir, Port, Clean, AdminLogin,
    AdminPass, Force. Короткие формы -d и -p тоже работают.

    ВНИМАНИЕ: PowerShell нечувствителен к регистру и запрещает алиас,
    совпадающий с именем параметра — [Alias('dir')] рядом с $Dir даёт
    ParameterNameConflictsWithAlias при загрузке. В алиасах только те имена,
    которых нет среди параметров ($Image, $Clean, $Force).

.EXAMPLE
    .\install-ppe.ps1
    Образ из ppe-tracker-api-data.tar рядом со скриптом, каталог C:\ppe.

.EXAMPLE
    .\install-ppe.ps1 -Image .\ppe-tracker-api-prod.tar -Clean -Dir D:\apps\ppe

.EXAMPLE
    .\install-ppe.ps1 -Image .\data.tar -p 8010 -AdminPass 'СложныйПароль1'

.EXAMPLE
    # Короткие ключи работают как в Linux
    .\install-ppe.ps1 -Image .\data.tar -d C:\ppe -p 8010
#>
[CmdletBinding()]
param(
    [string]$Image,

    [Alias('d')]
    [string]$Dir = "C:\ppe",

    [Alias('p')]
    [int]$Port = 8000,

    [switch]$Clean,

    [Alias('login')]
    [string]$AdminLogin = "admin",

    [Alias('pass')]
    [string]$AdminPass,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step($t) { Write-Host "==> $t" -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host "    $t" -ForegroundColor Green }
function Write-Warn($t) { Write-Host "    $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "    $t" -ForegroundColor Red }

function New-Secret([int]$Length) {
    # Без python: PowerShell сам умеет криптостойкую случайность
    $bytes = [byte[]]::new([int]([math]::Ceiling($Length * 3 / 4)))
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $s = [Convert]::ToBase64String($bytes) -replace '\+', '-' -replace '/', '_' -replace '=', ''
    return $s.Substring(0, [Math]::Min($Length, $s.Length))
}

# --- Окружение ------------------------------------------------------------
Write-Step "Проверяю окружение"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "нет docker в PATH - установите Docker Desktop"
    exit 1
}

$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
docker info *> $null
$infoCode = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($infoCode -ne 0) {
    Write-Err "демон Docker не отвечает - запустите Docker Desktop и дождитесь «Engine running»"
    exit 1
}

$ErrorActionPreference = 'Continue'
docker compose version *> $null
$composeCode = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($composeCode -ne 0) {
    Write-Err "нужен docker compose v2 (входит в Docker Desktop)"
    exit 1
}

Write-Ok "docker: $((docker --version) -replace '^Docker version ','')"

# --- Файл образа ----------------------------------------------------------
if (-not $Image) {
    foreach ($cand in @(
        "ppe-tracker-api-data.tar", "ppe-tracker-api-prod.tar",
        "ppe-tracker-api-data.tar.gz", "ppe-tracker-api-prod.tar.gz")) {
        $p = Join-Path $PSScriptRoot $cand
        if (Test-Path -LiteralPath $p) { $Image = $p; break }
    }
}
if (-not $Image) {
    Write-Err "не найден файл образа. Укажите: .\install-ppe.ps1 -Image ppe-tracker-api-data.tar"
    exit 1
}
if (-not (Test-Path -LiteralPath $Image)) {
    Write-Err "нет файла: $Image"
    exit 1
}

if ($Image -like "*.tar.gz") {
    Write-Step "Распаковываю $Image"
    $tar = $Image -replace '\.gz$', ''
    # gzip из Git/bin существует не всегда; .NET умеет всегда
    $in = [System.IO.File]::OpenRead($Image)
    try {
        $gz = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        try {
            $out = [System.IO.File]::Create($tar)
            try { $gz.CopyTo($out) } finally { $out.Dispose() }
        } finally { $gz.Dispose() }
    } finally { $in.Dispose() }
    $Image = $tar
    Write-Ok "получен $tar"
}

Write-Ok "образ: $Image"

# --- Каталог --------------------------------------------------------------
Write-Step "Каталог установки: $Dir"
if (-not (Test-Path -LiteralPath $Dir)) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Write-Ok "создан"
} else {
    Write-Ok "каталог существует"
}

# --- Загрузка -------------------------------------------------------------
Write-Step "Загружаю образ"
$loadOut = & docker load -i $Image 2>&1
if ($LASTEXITCODE -ne 0) {
    $loadOut | ForEach-Object { Write-Host $_ }
    Write-Err "docker load не удался"
    exit 1
}
Write-Ok "образ загружен"

# Тег берём из вывода load: на машине может лежать другой ppe-tracker-api:*
# (например, :data от прошлой сборки), и первая строка списка образов —
# не обязательно только что загруженный образ.
$loadText = ($loadOut | Out-String)
$imageName = $null
if ($loadText -match 'Loaded image:\s*(ppe-tracker-api:[^\s]+)') {
    $imageName = $Matches[1]
}
if (-not $imageName) {
    $imageName = (docker image ls --format '{{.Repository}}:{{.Tag}}' |
        Where-Object { $_ -like 'ppe-tracker-api:*' } | Select-Object -First 1)
}
if (-not $imageName) { Write-Err "в архиве нет образа ppe-tracker-api"; exit 1 }
Write-Ok "тег: $imageName"

if ($imageName -like '*:prod' -and -not $Clean) {
    Write-Warn "загружен чистый образ - включаю режим --clean"
    $Clean = $true
}
if ($imageName -like '*:data' -and $Clean) {
    Write-Warn "загружен образ с данными, но указан -Clean"
}

# --- .env -----------------------------------------------------------------
$envFile = Join-Path $Dir '.env'
$composeFile = Join-Path $Dir 'docker-compose.yml'
$keepEnv = $false

if ((Test-Path -LiteralPath $envFile) -and -not $Force) {
    Write-Warn "$envFile уже существует. Перезаписать? [y/N] "
    $answer = Read-Host
    if ($answer -notmatch '^(y|Y|yes|Yes)$') {
        $keepEnv = $true
        Write-Warn "оставляю существующий .env (секреты не меняются)"
    }
}

if (-not $keepEnv) {
    Write-Step "Генерирую секреты и .env"
    if (-not $AdminPass) { $AdminPass = New-Secret 18 }
    $secretKey = New-Secret 48
    $pgPass = New-Secret 24

    $content = @"
# PPE Tracker - окружение установки. Создано install-ppe.ps1 $(Get-Date -Format 'yyyy-MM-dd').
# Здесь секреты: не добавляйте файл в git и не пересылайте его.

SECRET_KEY=$secretKey
ENVIRONMENT=production
# true - только за HTTPS на reverse-proxy. Для локального http оставьте false.
SESSION_COOKIE_SECURE=false
# Применять миграции при старте: нужно при первом старте и после обновления.
AUTO_MIGRATE=1

POSTGRES_USER=ppe
POSTGRES_PASSWORD=$pgPass
POSTGRES_DB=ppe_db
# Хост базы внутри compose. Нужен образу с данными: entrypoint-data.sh
# подключается psql по этим переменным, а не через settings приложения.
POSTGRES_HOST=db
POSTGRES_PORT=5432

ADMIN_USERNAME=$AdminLogin
ADMIN_PASSWORD=$AdminPass
"@
    [System.IO.File]::WriteAllText($envFile, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "$envFile создан"
} else {
    $map = @{}
    Get-Content -LiteralPath $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$') { $map[$matches[1]] = $matches[2] }
    }
    if (-not $map['SECRET_KEY']) { Write-Err "в $envFile нет SECRET_KEY"; exit 1 }
    $AdminLogin = $map['ADMIN_USERNAME']; $AdminPass = $map['ADMIN_PASSWORD']
    Write-Ok "использую существующий $envFile"
}

# --- compose --------------------------------------------------------------
Write-Step "Пишу docker-compose.yml"
# Порт в шаблоне записан как ${Port} — обязательно в фигурных скобках.
# Внутри here-строки PowerShell читает "$Port:8000" как имя переменной
# "Port:8000" (её нет, значение пустое), строка превращается в "127.0.0.1:"
# и compose падает с "no port specified: 127.0.0.1:<empty>". Проверено
# на PowerShell 7: "127.0.0.1:$Port:8000" -> "127.0.0.1:".
$compose = @"
# Создано install-ppe.ps1. Правьте осторожно: при повторной установке с
# -Force файл перезаписывается.
services:
  api:
    image: $imageName
    container_name: ppe-api
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:${Port}:8000"
    volumes:
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
      POSTGRES_USER: `${POSTGRES_USER:?задайте POSTGRES_USER в .env}
      POSTGRES_PASSWORD: `${POSTGRES_PASSWORD:?задайте POSTGRES_PASSWORD в .env}
      POSTGRES_DB: `${POSTGRES_DB:?задайте POSTGRES_DB в .env}
    volumes:
      - ppe_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U `$`${POSTGRES_USER} -d `$`${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  ppe_pgdata:
  ppe_photos:
"@
$compose = $compose -replace '`\$\{', '${' -replace '`\$', '$'
# PowerShell 5.1 читает файл без BOM как ANSI; 7+ — как UTF-8. Без BOM на
# 5.1 кириллица в комментариях превратилась бы в мусор, поэтому пишем BOM.
Set-Content -LiteralPath $composeFile -Value $compose -Encoding UTF8
Write-Ok "$composeFile создан"

# Проверка сразу, а не на docker compose up: битый span в шаблоне (например,
# пустой порт) всплывает уже при up, и сообщение там невнятное
# ("no port specified: 127.0.0.1:<empty>"). config называет причину.
$composeCheck = & docker compose -f $composeFile config -q 2>&1
if ($LASTEXITCODE -ne 0) {
    $composeCheck | ForEach-Object { Write-Host $_ }
    Write-Err "docker-compose.yml некорректен — см. сообщение выше"
    exit 1
}
Write-Ok "docker-compose.yml проверен (docker compose config)"

# --- Запуск ---------------------------------------------------------------
Write-Step "Поднимаю контейнеры"
Push-Location $Dir
try {
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Err "docker compose up не удался. Логи: docker compose -f `"$composeFile`" logs"
        exit 1
    }

    Write-Step "Жду готовности приложения"
    $ready = $false
    for ($i = 1; $i -le 60; $i++) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/healthz" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch { }
        Start-Sleep -Seconds 2
    }
    if (-not $ready) {
        Write-Warn "приложение не ответило за 120 с"
        Write-Warn "логи: docker compose -f `"$composeFile`" logs --tail 50 api"
        exit 1
    }
    Write-Ok "приложение отвечает (healthz 200)"

    # --- Администратор ---------------------------------------------------
    if ($Clean) {
        Write-Step "Завожу администратора"
        $out = docker exec ppe-api python create_admin.py 2>&1 | Out-String
        if ($out -match 'уже существует') {
            Write-Warn "пользователь $AdminLogin уже был - пароль не менялся"
        } else {
            Write-Ok "администратор $AdminLogin создан"
        }
    } else {
        Write-Ok "образ с данными: учётка администратора пришла вместе с данными"
    }
} finally {
    Pop-Location
}

# --- Итог -----------------------------------------------------------------
Write-Host ""
Write-Step "Установка завершена"
Write-Host ""
Write-Host "  Адрес:      http://127.0.0.1:$Port"
Write-Host "  Логин:      $AdminLogin"
if ($Clean) {
    if ($AdminPass) { Write-Host "  Пароль:     $AdminPass" }
    else { Write-Host "  Пароль:     из $envFile (ADMIN_PASSWORD)" }
} else {
    Write-Host "  Пароль:     пароль администратора из dev-базы"
}
Write-Host "  Каталог:    $Dir"
Write-Host "  .env:       $envFile  (секреты - не пересылать)"
Write-Host ""
Write-Host "Управление:"
Write-Host "  cd $Dir"
Write-Host "  docker compose ps            # состояние"
Write-Host "  docker compose logs -f api   # логи"
Write-Host "  docker compose restart api   # перезапуск"
Write-Host "  docker compose down          # остановить (данные сохранятся)"
Write-Host ""
Write-Host "Резервная копия базы:"
Write-Host "  docker exec ppe-db sh -c 'pg_dump -U `$POSTGRES_USER -d `$POSTGRES_DB --no-owner' > backup_$(Get-Date -Format 'yyyy-MM-dd').sql"
Write-Host ""
Write-Host "Резервная копия фото (отдельно от дампа: файлы лежат на томе):"
Write-Host "  docker exec ppe-api tar czf - -C /app/data/photos . > photos_$(Get-Date -Format 'yyyy-MM-dd').tar.gz"
Write-Host ""

if (-not $Clean) {
    Write-Warn "в образе персональные данные сотрудников — не публикуйте образ в registry"
}

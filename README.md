# PPE Tracker

Учёт средств индивидуальной защиты (СИЗ) на предприятии: сотрудники, подразделения,
должности, нормы выдачи, фактические выдачи, размерные группы, импорт и экспорт Excel.

## Стек

- **Backend:** FastAPI, SQLAlchemy 2.0 (async), asyncpg, Alembic, Pydantic v2
- **Frontend:** Jinja2-шаблоны, Bootstrap 5, ванильный JS (без сборки)
- **БД:** PostgreSQL 16
- **Запуск:** Docker Compose

## Быстрый старт

```bash
cp .env.example .env
# в .env обязательно заполните SECRET_KEY:
python -c "import secrets; print(secrets.token_urlsafe(48))"

docker compose up -d --build
docker compose exec api alembic upgrade head
docker compose exec api python create_admin.py   # ADMIN_PASSWORD задаётся в .env
```

Приложение: <http://localhost:8000> — откроется страница входа.

### Локальный запуск без Docker

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export SECRET_KEY="$(python -c 'import secrets; print(secrets.token_urlsafe(48))')"
export POSTGRES_HOST=localhost

alembic upgrade head
uvicorn app.main:app --reload
```

## Роли

| Роль            | Права                                                                 |
|-----------------|-----------------------------------------------------------------------|
| `admin`         | Всё, включая управление пользователями                                |
| `safety_officer`| Сотрудники своего подразделения (опционально — вместе с дочерними)     |

Пользователь без привязки к подразделению видит все данные.

## API

Все эндпоинты `/api/v1/*`, кроме `/api/v1/auth/login` и `/api/v1/auth/logout`,
требуют активной сессии (cookie). Авторизация подключается централизованно в
`app/main.py`, поэтому новый роутер нельзя оставить открытым по забывчивости.

| Группа            | Префикс                        |
|-------------------|--------------------------------|
| Аутентификация    | `/api/v1/auth`                 |
| Сотрудники        | `/api/v1/employees`            |
| Подразделения     | `/api/v1/departments`          |
| Должности         | `/api/v1/positions`            |
| Нормы выдачи      | `/api/v1/position_ppe_norms`   |
| Выдачи СИЗ        | `/api/v1/employee_ppe_issues`  |
| Наименования СИЗ  | `/api/v1/ppe_items`            |
| Импорт / экспорт  | `/api/v1/import`, `/api/v1/export` |

WebSocket `/ws/employees/{id}` также требует сессии.

## Миграции

```bash
alembic upgrade head            # применить
alembic revision --autogenerate -m "описание"
alembic downgrade -1            # откатить одну
```

## Безопасность

- `SECRET_KEY` хранится только в `.env`; приложение не стартует без него.
- Пароли — bcrypt (`passlib`).
- Сессионная cookie: `HttpOnly`, `SameSite=Lax`, срок 7 дней; в продакшене
  включите `SESSION_COOKIE_SECURE=true` и работайте через HTTPS.

## Правила удаления

- Подразделение удаляется только пустым: если внутри есть дочерние подразделения,
  должности или сотрудники, API вернёт 400 с указанием причины. Сначала данные
  нужно перенести или удалить по отдельности.
- То же продублировано на уровне БД: у `positions.department_id` стоит
  `ON DELETE RESTRICT`, поэтому удаление в обход приложения тоже не пройдёт.

## Срок носки СИЗ

Дата окончания считается по календарю (`relativedelta`), а не как 365 дней за год
и 30 за месяц: 31 января + 1 месяц = 28/29 февраля, 29 февраля + 1 год = 28 февраля.
Норма «до износа» даёт пустой срок — он заполняется вручную.

## Импорт Excel

- Принимается только `.xlsx`; `.xls` отклоняется с подсказкой сохранить как `.xlsx`.
- Ограничения по умолчанию: 10 МБ и 5000 строк (`MAX_IMPORT_FILE_MB`,
  `MAX_IMPORT_ROWS` в `.env`).
- Каждая строка импортируется в своей SAVEPOINT: ошибка в одной строке не
  прерывает остальные, а попадает в список `errors` ответа (не больше 50 штук).

## Известные ограничения

- Нет CSRF-токенов (частично компенсируется `SameSite=Lax`); для форм,
  меняющих данные, стоит добавить.
- Нет автоматических тестов и CI.
- Серверной пагинации и поиска нет: списки фильтруются в браузере.
- Нормы удаляются по одной записи за запрос (массовое удаление — цикл на клиенте).

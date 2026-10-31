"""CSRF-защита для запросов, меняющих данные.

Схема — double-submit на сессии:
1. при отрисовке страницы в сессию кладётся случайный токен, он же уходит в HTML;
2. клиент присылает его в заголовке `X-CSRF-Token` для POST/PUT/PATCH/DELETE;
3. сервер сравнивает присланное со значением в сессии.

`SameSite=Lax` на cookie уже отсекает большинство сценариев, но не все:
запросы, инициированные со сторонних сайтов через истории/редиректы, и старые
браузеры без поддержки SameSite. Токен закрывает и это.
"""
import hmac
import secrets

from fastapi import HTTPException, Request, status

SESSION_KEY = "csrf_token"
HEADER_NAME = "X-CSRF-Token"
FORM_FIELD = "csrf_token"

# Методы, которые по RFC 7231 считаются безопасными и не меняют состояние
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS", "TRACE"})


def get_csrf_token(request: Request) -> str:
    """Возвращает токен из сессии, создавая его при первом обращении."""
    token = request.session.get(SESSION_KEY)
    if not token:
        token = secrets.token_urlsafe(32)
        request.session[SESSION_KEY] = token
    return token


def require_csrf(request: Request) -> None:
    """Проверяет токен для небезопасных методов. Бросает 403 при расхождении."""
    if request.method in SAFE_METHODS:
        return

    expected = request.session.get(SESSION_KEY)
    if not expected:
        # Сессии нет вообще — такой запрос и так не пройдёт авторизацию,
        # но явный отказ понятнее, чем «401» на любом эндпоинте
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Сессия не найдена, обновите страницу и войдите заново",
        )

    supplied = request.headers.get(HEADER_NAME) or request.headers.get(HEADER_NAME.lower())
    if not supplied:
        # На случай отправки обычной формы без JS
        supplied = request.query_params.get(FORM_FIELD)

    if not supplied or not hmac.compare_digest(str(supplied), str(expected)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Токен безопасности устарел. Обновите страницу и повторите действие",
        )


def csrf_token_for(request: Request) -> str:
    """Шаблонный хелпер: {{ csrf_token(request) }}."""
    return get_csrf_token(request)

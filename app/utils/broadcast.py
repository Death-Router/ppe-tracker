"""Утилита рассылки событий через WebSocket.

Рассылка — вспомогательная операция: если клиент отвалился или broadcast
не удался, операция всё равно должна завершиться успешно. Но молча глотать
исключение нельзя (ruff S110/BLE001): ошибку пишем в лог, чтобы проблемы
с WebSocket-каналом были видны, а не исчезали бесследно.
"""
import logging

from app.api.v1.endpoints.ws import manager

logger = logging.getLogger(__name__)


async def broadcast(employee_id: int, message: dict) -> None:
    """Отправляет событие подписчикам, не ломая основной запрос при сбое."""
    try:
        await manager.broadcast_to_employee(employee_id, message)
    except Exception:  # noqa: BLE001 — сбой рассылки не должен ронять запрос
        logger.warning(
            "Не удалось разослать событие %s (employee_id=%s)",
            message.get("event"),
            employee_id,
            exc_info=True,
        )

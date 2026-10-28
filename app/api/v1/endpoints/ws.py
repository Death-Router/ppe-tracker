from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter(tags=["WebSocket"])


class ConnectionManager:
    def __init__(self):
        # Храним активные соединения по ID сотрудника
        # {0: [ws_list_page], 1: [ws1, ws2], 2: [ws3]}
        # ID = 0 используется для страницы общего списка
        self.active_connections: dict[int, list[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, employee_id: int):
        await websocket.accept()
        if employee_id not in self.active_connections:
            self.active_connections[employee_id] = []
        self.active_connections[employee_id].append(websocket)

    def disconnect(self, websocket: WebSocket, employee_id: int):
        if employee_id in self.active_connections:
            if websocket in self.active_connections[employee_id]:
                self.active_connections[employee_id].remove(websocket)
            # Если больше никто не смотрит на этого сотрудника, очищаем память
            if not self.active_connections[employee_id]:
                del self.active_connections[employee_id]

    async def broadcast_to_employee(self, employee_id: int, message: dict):
        """Отправляет уведомление тем, кто смотрит на конкретного сотрудника,
        А ТАКЖЕ тем, кто смотрит на общий список (id=0)."""

        # Собираем уникальные соединения: подписчики конкретного ID + подписчики списка (0)
        targets = set(self.active_connections.get(employee_id, []))
        targets.update(self.active_connections.get(0, []))

        for connection in targets:
            try:
                await connection.send_json(message)
            except (WebSocketDisconnect, RuntimeError):
                # Если соединение мертво, отключаем его от всех каналов
                self.disconnect(connection, employee_id)
                self.disconnect(connection, 0)


manager = ConnectionManager()


@router.websocket("/ws/employees/{employee_id}")
async def websocket_endpoint(websocket: WebSocket, employee_id: int):
    await manager.connect(websocket, employee_id)
    try:
        while True:
            # Держим соединение открытым
            await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket, employee_id)

from datetime import date

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ppe_item import PpeItemRead


class EmployeePpeIssueBase(BaseModel):
    employee_id: int
    ppe_item_id: int
    issue_date: date
    quantity: str = Field("1", max_length=50)
    size_value: str | None = Field(None, max_length=50)
    # «лично/дозатор» — только для дерматологических СИЗ (сноска <*> карточки)
    issue_method: str | None = Field(None, pattern="^(лично|дозатор)$")
    # Графы 7-10 «Возвращено» и «Акт списания»
    returned_date: date | None = None
    returned_quantity: str | None = Field(None, max_length=50)
    write_off_act_date: date | None = None
    write_off_act_number: str | None = Field(None, max_length=50)

class EmployeePpeIssueCreate(EmployeePpeIssueBase):
    """Новая выдача.

    force — подтверждение повторной выдачи: если у сотрудника уже есть это СИЗ
    (остаток по прежним выдачам больше нуля), сервер отвечает 409 и просит
    подтверждение. Флаг в БД не пишется, он живёт только в запросе.
    """

    force: bool = False

class EmployeePpeIssueUpdate(BaseModel):
    """Правка возврата и акта списания по уже выданной записи.

    Отдельная схема, а не EmployeePpeIssueBase: менять дату выдачи, размер и
    количество задним числом нельзя — на них уже ссылается личная карточка.
    """
    issue_method: str | None = Field(None, pattern="^(лично|дозатор)$")
    returned_date: date | None = None
    returned_quantity: str | None = Field(None, max_length=50)
    write_off_act_date: date | None = None
    write_off_act_number: str | None = Field(None, max_length=50)
    version: int = Field(..., description="Текущая версия записи")

class EmployeePpeIssueRead(EmployeePpeIssueBase):
    id: int
    version: int
    expiry_date: date | None = None
    ppe_item: PpeItemRead | None = None
    model_config = ConfigDict(from_attributes=True)

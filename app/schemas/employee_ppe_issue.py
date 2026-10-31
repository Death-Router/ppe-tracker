from datetime import date

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ppe_item import PpeItemRead


class EmployeePpeIssueBase(BaseModel):
    employee_id: int
    ppe_item_id: int
    issue_date: date
    quantity: str = Field("1", max_length=50)
    size_value: str | None = Field(None, max_length=50)

class EmployeePpeIssueCreate(EmployeePpeIssueBase):
    pass

class EmployeePpeIssueRead(EmployeePpeIssueBase):
    id: int
    version: int
    expiry_date: date | None = None
    ppe_item: PpeItemRead | None = None
    model_config = ConfigDict(from_attributes=True)

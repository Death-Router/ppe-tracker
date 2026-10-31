from pydantic import BaseModel, ConfigDict, Field

from app.schemas.department import DepartmentRead


class PositionBase(BaseModel):
    name: str = Field(..., max_length=100)
    department_id: int

class PositionCreate(PositionBase):
    pass

class PositionRead(PositionBase):
    id: int
    version: int
    department: DepartmentRead | None = None
    model_config = ConfigDict(from_attributes=True)

class PositionUpdate(PositionBase):
    name: str | None = None
    department_id: int | None = None
    version: int

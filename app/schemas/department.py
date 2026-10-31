from pydantic import BaseModel, ConfigDict, Field


class DepartmentBase(BaseModel):
    name: str = Field(..., max_length=100)
    parent_id: int | None = None

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentRead(DepartmentBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class DepartmentUpdate(DepartmentBase):
    name: str | None = None
    parent_id: int | None = None
    version: int

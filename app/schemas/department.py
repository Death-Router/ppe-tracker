from pydantic import BaseModel, ConfigDict, Field

class DepartmentBase(BaseModel):
    name: str = Field(..., max_length=100)

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentRead(DepartmentBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class DepartmentUpdate(DepartmentBase):
    name: str | None = None
    version: int

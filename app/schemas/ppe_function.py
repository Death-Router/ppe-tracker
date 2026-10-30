from pydantic import BaseModel, ConfigDict, Field

class PpeFunctionBase(BaseModel):
    name: str = Field(..., max_length=100)

class PpeFunctionCreate(PpeFunctionBase):
    pass

class PpeFunctionRead(PpeFunctionBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class PpeFunctionUpdate(PpeFunctionBase):
    name: str | None = None
    version: int

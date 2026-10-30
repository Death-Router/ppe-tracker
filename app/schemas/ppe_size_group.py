from pydantic import BaseModel, ConfigDict, Field

class PpeSizeGroupBase(BaseModel):
    name: str = Field(..., max_length=100)

class PpeSizeGroupCreate(PpeSizeGroupBase):
    pass

class PpeSizeGroupRead(PpeSizeGroupBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class PpeSizeGroupUpdate(PpeSizeGroupBase):
    name: str | None = None
    version: int

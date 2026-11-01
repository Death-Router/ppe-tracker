from pydantic import BaseModel, ConfigDict, Field


class PpeSizeGroupBase(BaseModel):
    name: str = Field(..., max_length=100)
    description: str | None = Field(None, max_length=1000, description="Пояснение к группе")

class PpeSizeGroupCreate(PpeSizeGroupBase):
    pass

class PpeSizeGroupRead(PpeSizeGroupBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class PpeSizeGroupUpdate(BaseModel):
    name: str | None = None
    description: str | None = Field(None, max_length=1000)
    version: int

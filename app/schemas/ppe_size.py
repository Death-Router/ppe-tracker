from pydantic import BaseModel, ConfigDict, Field

class PpeSizeBase(BaseModel):
    size_group_id: int = Field(..., description="ID размерной группы")
    size_value: str = Field(..., max_length=50, description="Размер")
    gender: str | None = Field(None, pattern="^[МЖ]$")

class PpeSizeCreate(PpeSizeBase):
    pass

class PpeSizeRead(PpeSizeBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

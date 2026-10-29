from pydantic import BaseModel, ConfigDict, Field

class PpeSizeBase(BaseModel):
    ppe_item_id: int
    size_value: str = Field(..., max_length=50)

class PpeSizeCreate(PpeSizeBase):
    pass

class PpeSizeRead(PpeSizeBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

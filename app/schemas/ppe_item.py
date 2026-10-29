from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_category import PpeCategoryRead

class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=255, description="Наименование СИЗ")
    category_id: int = Field(..., description="ID категории")
    unit_id: int | None = Field(None, description="ID единицы измерения")

class PpeItemCreate(PpeItemBase):
    pass

class PpeItemRead(PpeItemBase):
    id: int
    version: int
    category: PpeCategoryRead | None = None
    unit: dict | None = None
    model_config = ConfigDict(from_attributes=True)

class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=255)
    category_id: int | None = None
    unit_id: int | None = None
    version: int

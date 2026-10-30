from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_function import PpeFunctionRead
from app.schemas.ppe_size_group import PpeSizeGroupRead
from app.schemas.unit import UnitRead

class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=255, description="Наименование СИЗ")
    function_id: int | None = Field(None, description="ID функции СИЗ")
    size_group_id: int | None = Field(None, description="ID размерной группы")
    unit_id: int | None = Field(None, description="ID единицы измерения")

class PpeItemCreate(PpeItemBase):
    pass

class PpeItemRead(PpeItemBase):
    id: int
    version: int
    function: PpeFunctionRead | None = None
    size_group: PpeSizeGroupRead | None = None
    unit: UnitRead | None = None
    model_config = ConfigDict(from_attributes=True)

class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=255)
    function_id: int | None = None
    size_group_id: int | None = None
    unit_id: int | None = None
    version: int

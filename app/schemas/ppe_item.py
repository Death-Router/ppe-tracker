from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ppe_function import PpeFunctionRead
from app.schemas.ppe_size_group import PpeSizeGroupRead
from app.schemas.unit import UnitRead


class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=255, description="Наименование СИЗ")
    function_id: int | None = Field(None, description="ID функции СИЗ")
    size_group_id: int | None = Field(None, description="ID размерной группы")
    unit_id: int | None = Field(None, description="ID единицы измерения")
    # Графа 2 оборотной стороны личной карточки: «Модель, марка, артикул,
    # класс защиты СИЗ, дерматологических СИЗ»
    model: str | None = Field(None, max_length=255, description="Модель, марка, артикул")
    protection_class: str | None = Field(None, max_length=100, description="Класс защиты")

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
    model: str | None = Field(None, max_length=255)
    protection_class: str | None = Field(None, max_length=100)
    version: int

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.position import PositionRead
from app.schemas.ppe_item import PpeItemRead


class PositionPpeNormBase(BaseModel):
    position_id: int = Field(..., description="ID должности")
    ppe_item_id: int = Field(..., description="ID наименования СИЗ")
    wear_period_value: str = Field(..., max_length=50, description="Срок (число)")
    wear_period_unit: str = Field(
        ..., max_length=20, description="Единица (год, месяц)"
    )
    quantity: str = Field(
        "1", max_length=50, description="Количество (например, 1 пара)"
    )


class PositionPpeNormCreate(PositionPpeNormBase):
    pass


class PositionPpeNormRead(PositionPpeNormBase):
    id: int
    version: int
    ppe_item: PpeItemRead | None = None
    position: PositionRead | None = None
    model_config = ConfigDict(from_attributes=True)


class PositionPpeNormUpdate(PositionPpeNormBase):
    wear_period_value: str | None = None
    wear_period_unit: str | None = None
    quantity: str | None = None
    version: int = Field(..., description="Текущая версия записи")

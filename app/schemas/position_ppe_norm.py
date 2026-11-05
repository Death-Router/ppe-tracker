from pydantic import BaseModel, ConfigDict, Field

from app.schemas.position import PositionRead
from app.schemas.ppe_item import PpeItemRead
from app.schemas.typical_norm import TypicalNormRead


class PositionPpeNormBase(BaseModel):
    position_id: int = Field(..., description="ID должности")
    ppe_item_id: int = Field(..., description="ID наименования СИЗ")
    # Пункт типовых отраслевых норм — графа «Пункт Норм» личной карточки
    typical_norm_id: int | None = Field(None, description="ID пункта норм")
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
    typical_norm: TypicalNormRead | None = None
    model_config = ConfigDict(from_attributes=True)


class PositionPpeNormUpdate(PositionPpeNormBase):
    position_id: int | None = None
    ppe_item_id: int | None = None
    typical_norm_id: int | None = None
    wear_period_value: str | None = None
    wear_period_unit: str | None = None
    quantity: str | None = None
    version: int = Field(..., description="Текущая версия записи")

from pydantic import BaseModel, ConfigDict, Field

class UnitBase(BaseModel):
    name: str = Field(..., max_length=50, description="Полное название (например, Пара)")
    short_name: str = Field(..., max_length=10, description="Сокращение (например, пар)")

class UnitCreate(UnitBase):
    pass

class UnitRead(UnitBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

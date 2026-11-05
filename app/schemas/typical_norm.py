from pydantic import BaseModel, ConfigDict, Field


class TypicalNormBase(BaseModel):
    clause: str = Field(..., max_length=50, description="Пункт нормы, например «п. 4»")
    description: str = Field(..., max_length=500, description="Описание нормы")

class TypicalNormCreate(TypicalNormBase):
    pass

class TypicalNormRead(TypicalNormBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)

class TypicalNormUpdate(BaseModel):
    clause: str | None = Field(None, max_length=50)
    description: str | None = Field(None, max_length=500)
    version: int

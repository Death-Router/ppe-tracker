from pydantic import BaseModel, ConfigDict, Field


class PpeCategoryBase(BaseModel):
    name: str = Field(..., max_length=100, description="Название категории")
    description: str | None = Field(
        None, max_length=500, description="Описание категории"
    )


class PpeCategoryCreate(PpeCategoryBase):
    pass


class PpeCategoryRead(PpeCategoryBase):
    id: int
    version: int
    model_config = ConfigDict(from_attributes=True)


class PpeCategoryUpdate(PpeCategoryBase):
    name: str | None = Field(None, max_length=100)
    description: str | None = Field(None, max_length=500)
    version: int = Field(..., description="Текущая версия записи")

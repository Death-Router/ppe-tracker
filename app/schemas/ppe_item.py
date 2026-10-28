from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ppe_category import PpeCategoryRead


class PpeItemBase(BaseModel):
    name: str = Field(..., max_length=150, description="Наименование СИЗ")
    category_id: int = Field(..., description="ID категории")


class PpeItemCreate(PpeItemBase):
    pass


class PpeItemRead(PpeItemBase):
    id: int
    version: int  # <--- ДОБАВИТЬ
    category: PpeCategoryRead | None = None

    model_config = ConfigDict(from_attributes=True)


class PpeItemUpdate(PpeItemBase):
    name: str | None = Field(None, max_length=150)
    category_id: int | None = None
    version: int = Field(..., description="Текущая версия записи")  # <--- СОЗДАТЬ СХЕМУ

from datetime import date
from pydantic import BaseModel, ConfigDict, Field
from app.schemas.ppe_item import PpeItemRead
from app.schemas.department import DepartmentRead
from app.schemas.position import PositionRead

# --- Схемы для размеров СИЗ ---
class PpeSizeCreate(BaseModel):
    ppe_item_id: int = Field(..., description="ID наименования СИЗ")
    size_value: str = Field(..., max_length=50, description="Размер")

class PpeSizeRead(BaseModel):
    ppe_item_id: int
    size_value: str
    ppe_item: PpeItemRead | None = None
    model_config = ConfigDict(from_attributes=True)

# --- Схемы для Сотрудника ---
class EmployeeBase(BaseModel):
    personnel_number: str = Field(..., max_length=20)
    last_name: str = Field(..., max_length=100)
    first_name: str = Field(..., max_length=100)
    middle_name: str | None = Field(None, max_length=100)
    
    # Делаем поля опциональными для чтения (чтобы старые данные не ломали список)
    department_id: int | None = Field(None, description="ID подразделения")
    position_id: int | None = Field(None, description="ID должности")
    
    hire_date: date | None = None
    position_change_date: date | None = None
    gender: str | None = Field(None, pattern="^[МЖ]$")
    height: str | None = Field(None, max_length=10)

class EmployeeCreate(EmployeeBase):
    # При создании делаем их обязательными
    department_id: int = Field(..., description="ID подразделения")
    position_id: int = Field(..., description="ID должности")
    ppe_sizes: list[PpeSizeCreate] = []

class EmployeeRead(EmployeeBase):
    id: int
    version: int
    ppe_sizes: list[PpeSizeRead] = []
    
    department_rel: DepartmentRead | None = None
    position_rel: PositionRead | None = None

    model_config = ConfigDict(from_attributes=True)

class EmployeeUpdate(EmployeeBase):
    personnel_number: str | None = None
    last_name: str | None = None
    first_name: str | None = None
    department_id: int | None = None
    position_id: int | None = None
    version: int = Field(..., description="Текущая версия записи")
    ppe_sizes: list[PpeSizeCreate] | None = None

from datetime import date

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.department import DepartmentRead
from app.schemas.position import PositionRead
from app.schemas.ppe_size_group import PpeSizeGroupRead


# --- Схемы для размеров сотрудника (привязаны к размерным группам) ---
class EmployeePpeSizeCreate(BaseModel):
    size_group_id: int = Field(..., description="ID размерной группы")
    size_value: str = Field(..., max_length=50, description="Размер")


class EmployeePpeSizeRead(BaseModel):
    size_group_id: int
    size_value: str
    size_group: PpeSizeGroupRead | None = None
    model_config = ConfigDict(from_attributes=True)


# --- Схемы для Сотрудника ---
class EmployeeBase(BaseModel):
    personnel_number: str = Field(..., max_length=20)
    last_name: str = Field(..., max_length=100)
    first_name: str = Field(..., max_length=100)
    middle_name: str | None = Field(None, max_length=100)
    department_id: int | None = None
    position_id: int | None = None
    hire_date: date | None = None
    position_change_date: date | None = None
    gender: str | None = Field(None, pattern="^[МЖ]$")
    height: str | None = Field(None, max_length=10)


class EmployeeCreate(EmployeeBase):
    middle_name: str = Field(..., max_length=100)
    department_id: int
    position_id: int
    hire_date: date
    gender: str = Field(..., pattern="^[МЖ]$")
    height: str = Field(..., max_length=10)
    ppe_sizes: list[EmployeePpeSizeCreate] = []


class EmployeeRead(EmployeeBase):
    id: int
    version: int
    ppe_sizes: list[EmployeePpeSizeRead] = []
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
    ppe_sizes: list[EmployeePpeSizeCreate] | None = None

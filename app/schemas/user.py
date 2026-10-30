from pydantic import BaseModel, ConfigDict, Field

class UserBase(BaseModel):
    username: str = Field(..., max_length=50)
    role: str = Field(..., description="admin или safety_officer")
    department_id: int | None = None
    include_subdepartments: bool = False
    is_active: bool = True

class UserCreate(UserBase):
    password: str = Field(..., min_length=6)

class UserRead(UserBase):
    id: int
    model_config = ConfigDict(from_attributes=True)

class UserUpdate(BaseModel):
    username: str | None = None
    password: str | None = None
    role: str | None = None
    department_id: int | None = None
    include_subdepartments: bool | None = None
    is_active: bool | None = None

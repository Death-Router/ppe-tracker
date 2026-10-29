from sqlalchemy.orm import DeclarativeBase

class Base(DeclarativeBase):
    pass

# Импортируем все модели, чтобы Alembic видел их при миграциях
from app.models.employee import Employee
from app.models.employee_ppe_size import EmployeePpeSize
from app.models.employee_ppe_issue import EmployeePpeIssue
from app.models.ppe_category import PpeCategory
from app.models.ppe_item import PpeItem
from app.models.ppe_size import PpeSize
from app.models.department import Department
from app.models.position import Position
from app.models.position_ppe_norm import PositionPpeNorm

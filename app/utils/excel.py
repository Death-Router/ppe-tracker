from io import BytesIO
from typing import Any

import pandas as pd


def generate_excel(data: list[dict[str, Any]], filename: str) -> BytesIO:
    """Генерирует Excel-файл из списка словарей."""
    if not data:  # noqa: SIM108 — с тернарником теряется комментарий о причине
        # Если данных нет, создаем пустой файл с заголовками
        df = pd.DataFrame(columns=["Нет данных"])
    else:
        df = pd.DataFrame(data)
    
    output = BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Данные')
    output.seek(0)
    return output

from io import BytesIO
import pandas as pd
from typing import List, Dict, Any

def generate_excel(data: List[Dict[str, Any]], filename: str) -> BytesIO:
    """Генерирует Excel-файл из списка словарей."""
    if not data:
        # Если данных нет, создаем пустой файл с заголовками
        df = pd.DataFrame(columns=["Нет данных"])
    else:
        df = pd.DataFrame(data)
    
    output = BytesIO()
    with pd.ExcelWriter(output, engine='openpyxl') as writer:
        df.to_excel(writer, index=False, sheet_name='Данные')
    output.seek(0)
    return output

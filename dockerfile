FROM python:3.11-slim

WORKDIR /app

# Копируем только requirements, чтобы кэшировать слой с зависимостями
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Копируем остальной код
COPY . .
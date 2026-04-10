FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PSCONNMON_DB_PATH=/data/psconnmon.duckdb
ENV PSCONNMON_IMPORT_MODE=local
ENV PSCONNMON_IMPORT_INTERVAL_SECONDS=30
ENV PSCONNMON_IMPORT_LOCAL_PATH=/data/import

WORKDIR /app

COPY pyproject.toml README.md /app/
COPY src /app/src

RUN pip install --upgrade pip \
    && pip install .

EXPOSE 8080

CMD ["python", "-m", "uvicorn", "psconnmon_service.app:app", "--host", "0.0.0.0", "--port", "8080"]

import pathlib
import os
from zoneinfo import ZoneInfo

# cron-выражение по умолчанию (путь берём из ENV, иначе дефолт)
CRON_FILE = pathlib.Path(os.environ.get("CRON_FILE", "/app/cron.txt"))

# часовой пояс сервера (по умолчанию Asia/Tbilisi)
SERVER_TZ = ZoneInfo(os.environ.get("SERVER_TZ", "Asia/Tbilisi"))

# пути к конфигу и БД
CONF_PATH = pathlib.Path(os.environ.get("CONF_PATH", "/opt/parser/config.json"))
DB_PATH   = pathlib.Path(os.environ.get("DB_PATH", "/app/runs.db"))

# директория для логов и JSON-отчётов
LOG_DIR = pathlib.Path(os.environ.get("LOG_DIR", "/app/logs"))

DATABASE_URL = os.environ.get("DATABASE_URL")
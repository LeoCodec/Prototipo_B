import os
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()
BASE_DIR = Path(__file__).resolve().parent

class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "dev-only-change-me")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL",
        f"sqlite:///{(BASE_DIR / 'instance' / 'prototipado_b.db').as_posix()}"
    )
    UPLOAD_FOLDER = BASE_DIR / "uploads"
    EXPORT_FOLDER = BASE_DIR / "exports"
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024
    DEMO_MODE = os.getenv("DEMO_MODE", "true").lower() == "true"
    TESSERACT_CMD = os.getenv("TESSERACT_CMD", "")

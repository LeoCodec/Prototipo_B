import os
import pytesseract
from flask import current_app
from .image_service import preprocess_for_ocr


def extract_text(path):
    cmd = current_app.config.get("TESSERACT_CMD", "")
    if cmd and os.path.exists(cmd):
        pytesseract.pytesseract.tesseract_cmd = cmd

    processed = preprocess_for_ocr(path)
    if processed is None:
        return "", "No se pudo abrir la imagen"

    try:
        text = pytesseract.image_to_string(processed, lang="spa")
        return text.strip(), ""
    except Exception as exc:
        return "", f"OCR no disponible: {exc}"

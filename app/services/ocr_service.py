from __future__ import annotations

import os
import cv2
import pytesseract
from PIL import Image


def _configure_tesseract():
    cmd = os.getenv("TESSERACT_CMD", "").strip()
    if cmd:
        pytesseract.pytesseract.tesseract_cmd = cmd


def _choose_language():
    preferred = os.getenv("OCR_LANG", "spa").strip() or "spa"
    try:
        installed = set(pytesseract.get_languages(config=""))
    except Exception:
        installed = set()

    if preferred in installed:
        return preferred
    if "spa" in installed:
        return "spa"
    if "eng" in installed:
        return "eng"
    return preferred


def preprocess_for_ocr(image_path):
    img = cv2.imread(str(image_path))
    if img is None:
        raise ValueError(f"No se pudo abrir la imagen: {image_path}")

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    h, w = gray.shape[:2]
    if max(h, w) < 2200:
        gray = cv2.resize(gray, None, fx=1.6, fy=1.6, interpolation=cv2.INTER_CUBIC)

    denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)
    blur = cv2.GaussianBlur(denoised, (3, 3), 0)
    _, thresholded = cv2.threshold(
        blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )
    return thresholded


def extract_text(image_path, psm=6, lang=None):
    _configure_tesseract()
    language = lang or _choose_language()
    config = f"--oem 3 --psm {int(psm)}"

    try:
        processed = preprocess_for_ocr(image_path)
        text = pytesseract.image_to_string(processed, lang=language, config=config).strip()

        data = pytesseract.image_to_data(
            processed,
            lang=language,
            config=config,
            output_type=pytesseract.Output.DICT,
        )

        confidences = []
        for raw in data.get("conf", []):
            try:
                value = float(raw)
            except (TypeError, ValueError):
                continue
            if value >= 0:
                confidences.append(value)

        avg_conf = round(sum(confidences) / len(confidences), 2) if confidences else 0.0

        return {
            "text": text,
            "language": language,
            "confidence": avg_conf,
            "error": None,
        }

    except Exception as exc:
        try:
            img = Image.open(image_path)
            text = pytesseract.image_to_string(img, lang=language, config=config).strip()
            return {
                "text": text,
                "language": language,
                "confidence": 0.0,
                "error": f"Fallback PIL usado: {exc}",
            }
        except Exception as fallback_exc:
            return {
                "text": "",
                "language": language,
                "confidence": 0.0,
                "error": f"OCR no disponible: {fallback_exc}",
            }


def run_ocr(image_path, *args, **kwargs):
    return extract_text(image_path, *args, **kwargs)

def ocr_image(image_path, *args, **kwargs):
    return extract_text(image_path, *args, **kwargs)

def extract_text_from_image(image_path, *args, **kwargs):
    return extract_text(image_path, *args, **kwargs)

def process_ocr(image_path, *args, **kwargs):
    return extract_text(image_path, *args, **kwargs)

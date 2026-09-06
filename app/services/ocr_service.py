from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import pytesseract
from pytesseract import Output


def _project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _resolve_tesseract() -> str:
    candidates = [
        os.getenv("TESSERACT_CMD"),
        shutil.which("tesseract"),
        r"C:\Program Files\Tesseract-OCR\tesseract.exe",
        r"C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(Path(candidate))
    return "tesseract"


def _resolve_tessdata() -> str | None:
    candidates = [
        os.getenv("TESSDATA_PREFIX"),
        str(_project_root() / "tools" / "tessdata"),
        r"C:\Program Files\Tesseract-OCR\tessdata",
        r"C:\Program Files (x86)\Tesseract-OCR\tessdata",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return str(Path(candidate))
    return None


def _configure() -> tuple[str, str | None]:
    cmd = _resolve_tesseract()
    pytesseract.pytesseract.tesseract_cmd = cmd

    tessdata = _resolve_tessdata()
    if tessdata:
        os.environ["TESSDATA_PREFIX"] = tessdata

    return cmd, tessdata


def _available_languages() -> list[str]:
    try:
        return pytesseract.get_languages(config="")
    except Exception:
        return []


def _language() -> str:
    requested = (os.getenv("OCR_LANG") or "spa").strip()
    available = _available_languages()

    if requested in available:
        return requested
    if "spa" in available:
        return "spa"
    if "eng" in available:
        return "eng"
    return requested


def _read_image(path: str):
    # imdecode tolera mejor rutas Windows con caracteres especiales.
    data = np.fromfile(path, dtype=np.uint8)
    image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError("No fue posible abrir la imagen.")
    return image


def _variants(image):
    height, width = image.shape[:2]

    # Estandarizar tamanio sin hacer enormes las fotos del celular.
    longest = max(height, width)
    if longest > 2200:
        scale = 2200.0 / longest
        image = cv2.resize(
            image,
            (int(width * scale), int(height * scale)),
            interpolation=cv2.INTER_AREA,
        )
    elif longest < 1400:
        scale = 1400.0 / max(longest, 1)
        image = cv2.resize(
            image,
            (int(width * scale), int(height * scale)),
            interpolation=cv2.INTER_CUBIC,
        )

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)

    otsu = cv2.threshold(
        denoised, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )[1]

    adaptive = cv2.adaptiveThreshold(
        denoised,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        12,
    )

    return [
        ("gris", gray),
        ("otsu", otsu),
        ("adaptativo", adaptive),
    ]


def _data_to_text(data: dict[str, list[Any]]) -> str:
    lines: dict[tuple[int, int, int], list[str]] = {}

    count = len(data.get("text", []))
    for i in range(count):
        token = str(data["text"][i] or "").strip()
        if not token:
            continue

        key = (
            int(data.get("block_num", [0] * count)[i] or 0),
            int(data.get("par_num", [0] * count)[i] or 0),
            int(data.get("line_num", [0] * count)[i] or 0),
        )
        lines.setdefault(key, []).append(token)

    return "\n".join(" ".join(tokens) for _, tokens in sorted(lines.items()))


def _mean_confidence(data: dict[str, list[Any]]) -> float:
    values = []
    for raw in data.get("conf", []):
        try:
            value = float(raw)
            if value >= 0:
                values.append(value)
        except (TypeError, ValueError):
            pass
    return round(sum(values) / len(values), 2) if values else 0.0


def extract_text(path: str) -> dict[str, Any]:
    cmd, tessdata = _configure()
    lang = _language()

    result = {
        "text": "",
        "language": lang,
        "confidence": 0.0,
        "preprocessing": "",
        "tesseract_cmd": cmd,
        "tessdata": tessdata or "",
        "error": None,
    }

    try:
        image = _read_image(path)
        best = None

        for variant_name, variant in _variants(image):
            config = "--oem 3 --psm 6"

            data = pytesseract.image_to_data(
                variant,
                lang=lang,
                config=config,
                output_type=Output.DICT,
            )

            text = _data_to_text(data).strip()
            confidence = _mean_confidence(data)
            score = confidence + min(len(text) / 1000.0, 10.0)

            candidate = {
                "text": text,
                "confidence": confidence,
                "preprocessing": variant_name,
                "score": score,
            }

            if best is None or candidate["score"] > best["score"]:
                best = candidate

        if best:
            result["text"] = best["text"]
            result["confidence"] = best["confidence"]
            result["preprocessing"] = best["preprocessing"]

        if not result["text"]:
            result["error"] = (
                "OCR ejecutado, pero no se detecto texto util. "
                "Revise encuadre, enfoque o confirme el contenido manualmente."
            )

    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"

    return result


# Alias compatibles con versiones anteriores.
run_ocr = extract_text
ocr_image = extract_text
extract_text_from_image = extract_text
process_ocr = extract_text

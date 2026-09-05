from __future__ import annotations

import re


FIELD_PATTERNS = {
    "nombre_alumno": [
        r"NOMBRE\s+DEL\s+NIÑ[OA]\s*[:\-]?\s*(.+)",
        r"NOMBRE\s+DEL\s+ALUMN[OA]\s*[:\-]?\s*(.+)",
    ],
    "fecha_nacimiento": [
        r"FECHA\s+DE\s+NACIMIENTO\s*[:\-]?\s*([0-9A-Za-zÁÉÍÓÚáéíóú/\- ]{5,30})",
    ],
    "telefono": [
        r"(?:TEL[ÉE]FONO|CEL(?:ULAR)?)\s*[:\-]?\s*([0-9 ()+\-]{8,20})",
    ],
    "codigo_postal": [
        r"(?:C\.?P\.?|C[ÓO]DIGO\s+POSTAL)\s*[:\-]?\s*(\d{5})",
    ],
    "domicilio": [
        r"DOMICILIO\s*[:\-]?\s*(.+)",
    ],
    "total_ingresos": [
        r"TOTAL\s+DE\s+INGRESOS\s*[:\-]?\s*\$?\s*([\d,.\s]+)",
        r"INGRESO\s+TOTAL\s*[:\-]?\s*\$?\s*([\d,.\s]+)",
    ],
    "total_gastos": [
        r"(?:TOTAL\s+DE\s+GASTOS|GASTO\s+TOTAL)\s*[:\-]?\s*\$?\s*([\d,.\s]+)",
    ],
}


def normalize_text(text):
    text = text.replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _clean_value(value):
    value = value.strip(" \t:;-")
    return re.sub(r"\s{2,}", " ", value).strip()


def extract_fields(text):
    normalized = normalize_text(text)
    result = {}

    for field, patterns in FIELD_PATTERNS.items():
        detected = ""
        for pattern in patterns:
            match = re.search(pattern, normalized, flags=re.IGNORECASE | re.MULTILINE)
            if match:
                detected = _clean_value(match.group(1))
                break

        result[field] = {
            "detected": detected,
            "confirmed": detected,
            "confidence": 0.75 if detected else 0.0,
        }

    return result


def combine_ocr_text(images):
    chunks = []
    for image in images:
        text = (getattr(image, "confirmed_text", None) or getattr(image, "ocr_text", None) or "").strip()
        if text:
            page = getattr(image, "page_number", "?")
            chunks.append(f"--- PAGINA {page} ---\n{text}")
    return "\n\n".join(chunks)

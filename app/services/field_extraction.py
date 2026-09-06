from __future__ import annotations

import re
from typing import Any


FIELD_DEFINITIONS = {
    "grado_solicita": {
        "label": "Grado que solicita",
        "aliases": ["GRADO QUE SOLICITA", "GRADO SOLICITADO"],
    },
    "fecha_entrevista": {
        "label": "Fecha de entrevista",
        "aliases": ["FECHA ENTREVISTA", "FECHA DE ENTREVISTA"],
    },
    "nombre_alumno": {
        "label": "Nombre del alumno",
        "aliases": [
            "NOMBRE DEL NINO", "NOMBRE DEL NIÃ‘O", "NOMBRE DEL ALUMNO",
            "NOMBRE DE LA NINA", "NOMBRE DE LA NIÃ‘A"
        ],
    },
    "edad": {"label": "Edad", "aliases": ["EDAD"]},
    "fecha_nacimiento": {
        "label": "Fecha de nacimiento",
        "aliases": ["FECHA DE NACIMIENTO"],
    },
    "domicilio": {"label": "Domicilio", "aliases": ["DOMICILIO"]},
    "telefono": {
        "label": "Telefono",
        "aliases": ["TELEFONO", "TELÃ‰FONO", "CELULAR", "TEL."],
    },
    "total_ingresos": {
        "label": "Total de ingresos",
        "aliases": ["TOTAL DE INGRESOS", "INGRESO TOTAL", "TOTAL INGRESOS"],
    },
    "predial": {"label": "Predial", "aliases": ["IMPUESTO PREDIAL", "PREDIAL"]},
    "renta": {"label": "Renta", "aliases": ["RENTA"]},
    "luz": {"label": "Luz", "aliases": ["LUZ"]},
    "agua": {"label": "Agua", "aliases": ["AGUA"]},
    "telefono_gasto": {
        "label": "Telefono (gasto)",
        "aliases": ["TELEFONO", "TELÃ‰FONO"],
    },
    "gas": {"label": "Gas", "aliases": ["GAS"]},
    "alimentos": {"label": "Alimentos", "aliases": ["ALIMENTOS"]},
    "automovil": {"label": "Automovil", "aliases": ["AUTOMOVIL", "AUTOMÃ“VIL"]},
    "pasajes": {"label": "Pasajes", "aliases": ["PASAJES"]},
    "colegiaturas": {"label": "Colegiaturas", "aliases": ["COLEGIATURAS"]},
    "vestido": {"label": "Vestido", "aliases": ["VESTIDO"]},
    "medico_medicinas": {
        "label": "Medico y medicinas",
        "aliases": ["MEDICO Y MEDICINAS", "MÃ‰DICO Y MEDICINAS"],
    },
    "muebles_hogar": {
        "label": "Muebles del hogar",
        "aliases": ["MUEBLES DEL HOGAR"],
    },
    "creditos_personales": {
        "label": "Creditos personales",
        "aliases": ["CREDITOS PERSONALES", "CRÃ‰DITOS PERSONALES"],
    },
    "otros_gastos": {
        "label": "Otros gastos",
        "aliases": ["OTROS GASTOS"],
    },
    "servicio_medico": {
        "label": "Servicio medico",
        "aliases": ["SERVICIO MEDICO", "SERVICIO MÃ‰DICO"],
    },
    "enfermedades_cronicas": {
        "label": "Enfermedades cronicas",
        "aliases": [
            "ENFERMEDADES CRONICAS EN LA FAMILIA",
            "ENFERMEDADES CRÃ“NICAS EN LA FAMILIA",
        ],
    },
    "tiempo_libre": {"label": "Tiempo libre", "aliases": ["TIEMPO LIBRE"]},
    "referencias": {"label": "Referencias", "aliases": ["REFERENCIAS"]},
    "observaciones": {"label": "Observaciones", "aliases": ["OBSERVACIONES"]},
}


def normalize_text(text: str) -> str:
    text = (text or "").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _line_value(lines: list[str], aliases: list[str]) -> tuple[str, float]:
    for i, line in enumerate(lines):
        upper = line.upper()

        for alias in aliases:
            alias_upper = alias.upper()

            if alias_upper not in upper:
                continue

            # Valor en la misma linea.
            match = re.search(
                re.escape(alias),
                line,
                flags=re.IGNORECASE,
            )
            tail = line[match.end():] if match else ""
            tail = re.sub(r"^[\s:;=\-_.]+", "", tail).strip()

            if tail:
                return tail, 0.82

            # Valor en la linea inmediatamente siguiente.
            if i + 1 < len(lines):
                nxt = lines[i + 1].strip()
                if nxt and len(nxt) <= 220:
                    return nxt, 0.62

    return "", 0.0


def _observations_block(lines: list[str]) -> tuple[str, float]:
    for i, line in enumerate(lines):
        if "OBSERVACIONES" not in line.upper():
            continue

        collected = []
        tail = re.sub(
            r"^.*?OBSERVACIONES\s*[:\-]?\s*",
            "",
            line,
            flags=re.IGNORECASE,
        ).strip()

        if tail:
            collected.append(tail)

        for nxt in lines[i + 1:i + 4]:
            upper = nxt.upper()
            if any(
                alias in upper
                for definition in FIELD_DEFINITIONS.values()
                for alias in definition["aliases"]
                if alias != "OBSERVACIONES"
            ):
                break
            if nxt.strip():
                collected.append(nxt.strip())

        value = " ".join(collected).strip()
        return value, 0.58 if value else 0.0

    return "", 0.0


def extract_fields(text: str) -> dict[str, dict[str, Any]]:
    normalized = normalize_text(text)
    lines = [line.strip() for line in normalized.splitlines() if line.strip()]
    result: dict[str, dict[str, Any]] = {}

    for field_name, definition in FIELD_DEFINITIONS.items():
        if field_name == "observaciones":
            detected, confidence = _observations_block(lines)
        else:
            detected, confidence = _line_value(lines, definition["aliases"])

        result[field_name] = {
            "label": definition["label"],
            "detected": detected,
            "confirmed": detected,
            "confidence": confidence,
        }

    cp = re.search(
        r"\b(?:C\.?\s*P\.?|CP)\s*[:\-]?\s*(\d{5})\b",
        normalized,
        flags=re.IGNORECASE,
    )
    result["codigo_postal"] = {
        "label": "Codigo postal",
        "detected": cp.group(1) if cp else "",
        "confirmed": cp.group(1) if cp else "",
        "confidence": 0.90 if cp else 0.0,
    }

    return result


def combine_ocr_text(images) -> str:
    chunks = []

    for image in images:
        text = (
            getattr(image, "confirmed_text", None)
            or getattr(image, "ocr_text", None)
            or ""
        ).strip()

        if text:
            chunks.append(
                f"--- PAGINA {getattr(image, 'page_number', '?')} ---\n{text}"
            )

    return "\n\n".join(chunks)

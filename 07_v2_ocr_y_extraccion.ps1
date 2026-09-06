param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS7 v2 OCR + EXTRACCION EN ESPANOL" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

# Dependencias Python del OCR.
if (-not (Select-String -Path "requirements.txt" -Pattern '^\s*pytesseract\b' -Quiet)) {
    Add-Content "requirements.txt" "`npytesseract>=0.3.13"
}
& $Py -m pip install -r requirements.txt

@'
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
            if tessdata:
                config += f' --tessdata-dir "{tessdata}"'

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
'@ | Set-Content -Encoding UTF8 "app\services\ocr_service.py"

@'
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
            "NOMBRE DEL NINO", "NOMBRE DEL NIÑO", "NOMBRE DEL ALUMNO",
            "NOMBRE DE LA NINA", "NOMBRE DE LA NIÑA"
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
        "aliases": ["TELEFONO", "TELÉFONO", "CELULAR", "TEL."],
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
        "aliases": ["TELEFONO", "TELÉFONO"],
    },
    "gas": {"label": "Gas", "aliases": ["GAS"]},
    "alimentos": {"label": "Alimentos", "aliases": ["ALIMENTOS"]},
    "automovil": {"label": "Automovil", "aliases": ["AUTOMOVIL", "AUTOMÓVIL"]},
    "pasajes": {"label": "Pasajes", "aliases": ["PASAJES"]},
    "colegiaturas": {"label": "Colegiaturas", "aliases": ["COLEGIATURAS"]},
    "vestido": {"label": "Vestido", "aliases": ["VESTIDO"]},
    "medico_medicinas": {
        "label": "Medico y medicinas",
        "aliases": ["MEDICO Y MEDICINAS", "MÉDICO Y MEDICINAS"],
    },
    "muebles_hogar": {
        "label": "Muebles del hogar",
        "aliases": ["MUEBLES DEL HOGAR"],
    },
    "creditos_personales": {
        "label": "Creditos personales",
        "aliases": ["CREDITOS PERSONALES", "CRÉDITOS PERSONALES"],
    },
    "otros_gastos": {
        "label": "Otros gastos",
        "aliases": ["OTROS GASTOS"],
    },
    "servicio_medico": {
        "label": "Servicio medico",
        "aliases": ["SERVICIO MEDICO", "SERVICIO MÉDICO"],
    },
    "enfermedades_cronicas": {
        "label": "Enfermedades cronicas",
        "aliases": [
            "ENFERMEDADES CRONICAS EN LA FAMILIA",
            "ENFERMEDADES CRÓNICAS EN LA FAMILIA",
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
'@ | Set-Content -Encoding UTF8 "app\services\field_extraction.py"

@'
from __future__ import annotations

import json
from pathlib import Path

from flask import (
    Blueprint, current_app, flash, redirect,
    render_template, url_for
)

from app.extensions import db
from app.models.study import Study
from app.services.field_extraction import combine_ocr_text, extract_fields
from app.services.ocr_service import extract_text


fields_bp = Blueprint("fields", __name__, url_prefix="/fields")


def _json_path(study_id: int) -> Path:
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"


def _load(study_id: int) -> dict:
    path = _json_path(study_id)

    if not path.exists():
        return {
            "study_id": study_id,
            "fields": {},
            "source_text": "",
            "context_notes": "",
            "human_reviewed": False,
        }

    return json.loads(path.read_text(encoding="utf-8"))


def _save(study_id: int, payload: dict) -> None:
    _json_path(study_id).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _upload_path(filename: str) -> Path | None:
    configured = current_app.config.get("UPLOAD_FOLDER")

    candidates = []
    if configured:
        candidates.append(Path(configured) / filename)

    project_root = Path(current_app.root_path).parent
    candidates.append(project_root / "uploads" / filename)

    for candidate in candidates:
        if candidate.exists():
            return candidate

    upload_root = project_root / "uploads"
    if upload_root.exists():
        found = next(upload_root.rglob(filename), None)
        if found:
            return found

    return None


@fields_bp.get("/<int:study_id>")
def detected(study_id: int):
    study = Study.query.get_or_404(study_id)
    return render_template(
        "fields_detected.html",
        study=study,
        payload=_load(study_id),
    )


@fields_bp.post("/<int:study_id>/reprocess")
def reprocess(study_id: int):
    study = Study.query.get_or_404(study_id)

    processed = 0
    failed = 0

    for image in study.images:
        path = _upload_path(image.filename)

        if not path:
            image.ocr_error = "No se encontro el archivo de imagen."
            failed += 1
            continue

        result = extract_text(str(path))
        image.ocr_text = result.get("text", "")
        image.ocr_error = result.get("error")

        if result.get("text"):
            processed += 1
        else:
            failed += 1

    db.session.commit()

    if processed:
        flash(
            f"OCR reprocesado: {processed} pagina(s) con texto. "
            f"{failed} pagina(s) requieren revision.",
            "success",
        )
    else:
        flash(
            "No se obtuvo texto OCR. Revise la calidad de la captura "
            "o confirme la informacion manualmente.",
            "warning",
        )

    return redirect(url_for("fields.detected", study_id=study.id))


@fields_bp.post("/<int:study_id>/run")
def run(study_id: int):
    study = Study.query.get_or_404(study_id)
    source_text = combine_ocr_text(study.images)

    payload = _load(study_id)
    payload.update({
        "study_id": study.id,
        "folio": study.folio,
        "fields": extract_fields(source_text),
        "source_text": source_text,
        "human_reviewed": False,
    })

    _save(study_id, payload)

    if source_text:
        flash("Extraccion preliminar completada.", "success")
    else:
        flash(
            "No hay texto OCR disponible. Use primero 'Reprocesar OCR'.",
            "warning",
        )

    return redirect(url_for("fields.detected", study_id=study.id))
'@ | Set-Content -Encoding UTF8 "app\routes\fields.py"

@'
{% extends "base.html" %}
{% block title %}Campos detectados{% endblock %}
{% block page_name %}Extracci&oacute;n por campos{% endblock %}

{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS7 &middot; DATOS PRELIMINARES</span>
    <h1>Campos detectados</h1>
    <p>{{ study.folio }} &middot; {{ study.student_name }}</p>
  </div>

  <div class="bottom-actions">
    <form method="POST" action="{{ url_for('fields.reprocess', study_id=study.id) }}">
      <button class="btn" type="submit">
        <i class="bi bi-arrow-repeat"></i> Reprocesar OCR
      </button>
    </form>

    <form method="POST" action="{{ url_for('fields.run', study_id=study.id) }}">
      <button class="btn btn-primary" type="submit">
        <i class="bi bi-magic"></i> Extraer campos
      </button>
    </form>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-exclamation-triangle notice-icon"></i>
  <div>
    <strong>La extracci&oacute;n es preliminar.</strong>
    <p>
      El texto manuscrito y la letra cursiva pueden requerir correcci&oacute;n humana.
    </p>
  </div>
</div>

<section class="section">
  <div class="review-card">
    {% if payload.fields %}
      <div class="review-stack">
      {% for name, item in payload.fields.items() %}
        <div style="display:grid;grid-template-columns:220px minmax(260px,1fr) 70px;gap:12px;align-items:center;margin-bottom:10px">
          <strong>{{ item.label or name.replace('_',' ')|title }}</strong>
          <input value="{{ item.detected }}" readonly>
          <small>{{ ((item.confidence or 0) * 100)|round|int }}%</small>
        </div>
      {% endfor %}
      </div>

      <div class="bottom-actions">
        <a class="btn btn-primary"
           href="{{ url_for('review_fields.review', study_id=study.id) }}">
          Continuar a revisi&oacute;n
        </a>
      </div>
    {% else %}
      <p>
        A&uacute;n no hay campos extra&iacute;dos.
        Si el expediente es anterior a la instalaci&oacute;n de Tesseract,
        pulse primero <strong>Reprocesar OCR</strong> y luego
        <strong>Extraer campos</strong>.
      </p>
    {% endif %}
  </div>
</section>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\fields_detected.html"

# Asegurar meta charset en base.html sin romper el template.
$patch = @'
from pathlib import Path

p = Path("app/templates/base.html")
if p.exists():
    text = p.read_text(encoding="utf-8", errors="replace")
    lower = text.lower()

    if 'charset=' not in lower:
        if '<head>' in lower:
            idx = lower.index('<head>') + len('<head>')
            text = text[:idx] + '\n  <meta charset="UTF-8">' + text[idx:]
        else:
            text = '<meta charset="UTF-8">\n' + text

    p.write_text(text, encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ippliap_ps7v2_charset.py"
$patch | Set-Content -Encoding UTF8 $tmp
& $Py $tmp
Remove-Item $tmp -Force

Write-Host ""
Write-Host "PS7 v2 instalado." -ForegroundColor Green
Write-Host "Flujo:" -ForegroundColor Cyan
Write-Host "  /fields/ID -> Reprocesar OCR -> Extraer campos -> Revision"
Write-Host ""

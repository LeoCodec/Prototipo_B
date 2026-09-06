param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS7 - EXTRACCION POR CAMPOS ===" -ForegroundColor Green

New-Item -ItemType Directory -Force "instance\field_extractions" | Out-Null

@'
from __future__ import annotations
import re

FIELD_LABELS = {
    "grado_solicita": ["GRADO QUE SOLICITA", "GRADO SOLICITADO"],
    "fecha_entrevista": ["FECHA ENTREVISTA", "FECHA DE ENTREVISTA"],
    "nombre_alumno": ["NOMBRE DEL NIÑO", "NOMBRE DEL NINO", "NOMBRE DEL ALUMNO", "NOMBRE DE LA NIÑA"],
    "edad": ["EDAD"],
    "fecha_nacimiento": ["FECHA DE NACIMIENTO"],
    "domicilio": ["DOMICILIO"],
    "telefono": ["TELEFONO", "TELÉFONO", "CEL", "CELULAR"],
    "total_ingresos": ["TOTAL DE INGRESOS", "INGRESO TOTAL"],
    "predial": ["IMPUESTO PREDIAL", "PREDIAL"],
    "renta": ["RENTA"],
    "luz": ["LUZ"],
    "agua": ["AGUA"],
    "telefono_gasto": ["TELEFONO", "TELÉFONO"],
    "gas": ["GAS"],
    "alimentos": ["ALIMENTOS"],
    "automovil": ["AUTOMOVIL", "AUTOMÓVIL"],
    "pasajes": ["PASAJES"],
    "colegiaturas": ["COLEGIATURAS"],
    "vestido": ["VESTIDO"],
    "medico_medicinas": ["MEDICO Y MEDICINAS", "MÉDICO Y MEDICINAS"],
    "muebles_hogar": ["MUEBLES DEL HOGAR"],
    "creditos_personales": ["CREDITOS PERSONALES", "CRÉDITOS PERSONALES"],
    "otros_gastos": ["OTROS GASTOS"],
    "servicio_medico": ["SERVICIO MEDICO", "SERVICIO MÉDICO"],
    "enfermedades_cronicas": ["ENFERMEDADES CRONICAS EN LA FAMILIA", "ENFERMEDADES CRÓNICAS EN LA FAMILIA"],
    "tiempo_libre": ["TIEMPO LIBRE"],
    "referencias": ["REFERENCIAS"],
    "observaciones": ["OBSERVACIONES"],
}

def normalize_text(text):
    text = (text or "").replace("\r", "\n")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()

def _line_value(lines, labels):
    for i, line in enumerate(lines):
        upper = line.upper()
        for label in labels:
            if label.upper() in upper:
                parts = re.split(re.escape(label), line, flags=re.IGNORECASE, maxsplit=1)
                tail = re.sub(r"^[\s:;=\-_.]+", "", parts[-1]).strip()
                if tail:
                    return tail, 0.82
                if i + 1 < len(lines):
                    nxt = lines[i + 1].strip()
                    if nxt and len(nxt) < 180:
                        return nxt, 0.62
    return "", 0.0

def extract_fields(text):
    normalized = normalize_text(text)
    lines = [x.strip() for x in normalized.splitlines() if x.strip()]
    result = {}

    for field, labels in FIELD_LABELS.items():
        detected, confidence = _line_value(lines, labels)
        result[field] = {
            "detected": detected,
            "confirmed": detected,
            "confidence": confidence,
        }

    cp = re.search(r"\b(?:C\.?\s*P\.?|CP)\s*[:\-]?\s*(\d{5})\b", normalized, re.I)
    result["codigo_postal"] = {
        "detected": cp.group(1) if cp else "",
        "confirmed": cp.group(1) if cp else "",
        "confidence": 0.90 if cp else 0.0,
    }
    return result

def combine_ocr_text(images):
    chunks = []
    for image in images:
        text = (
            getattr(image, "confirmed_text", None)
            or getattr(image, "ocr_text", None)
            or ""
        ).strip()
        if text:
            chunks.append(f"--- PAGINA {getattr(image, 'page_number', '?')} ---\n{text}")
    return "\n\n".join(chunks)
'@ | Set-Content -Encoding UTF8 "app\services\field_extraction.py"

@'
from __future__ import annotations
import json
from pathlib import Path

from flask import Blueprint, current_app, render_template, redirect, url_for, flash

from app.models.study import Study
from app.services.field_extraction import combine_ocr_text, extract_fields

fields_bp = Blueprint("fields", __name__, url_prefix="/fields")

def _path(study_id):
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"

def _load(study_id):
    p = _path(study_id)
    if not p.exists():
        return {"study_id": study_id, "fields": {}, "source_text": "", "context_notes": ""}
    return json.loads(p.read_text(encoding="utf-8"))

@fields_bp.get("/<int:study_id>")
def detected(study_id):
    study = Study.query.get_or_404(study_id)
    return render_template("fields_detected.html", study=study, payload=_load(study_id))

@fields_bp.post("/<int:study_id>/run")
def run(study_id):
    study = Study.query.get_or_404(study_id)
    source_text = combine_ocr_text(study.images)
    payload = {
        "study_id": study.id,
        "folio": study.folio,
        "fields": extract_fields(source_text),
        "source_text": source_text,
        "context_notes": "",
        "human_reviewed": False,
    }
    _path(study_id).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    flash("Extracción preliminar completada." if source_text else "No hay texto OCR disponible todavía.", "success" if source_text else "warning")
    return redirect(url_for("fields.detected", study_id=study.id))
'@ | Set-Content -Encoding UTF8 "app\routes\fields.py"

@'
{% extends "base.html" %}
{% block title %}Campos detectados{% endblock %}
{% block page_name %}Extracción por campos{% endblock %}
{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS7 · DATOS PRELIMINARES</span>
    <h1>Campos detectados</h1>
    <p>{{ study.folio }} · {{ study.student_name }}</p>
  </div>
  <form method="POST" action="{{ url_for('fields.run', study_id=study.id) }}">
    <button class="btn btn-primary"><i class="bi bi-magic"></i> Ejecutar extracción</button>
  </form>
</section>

<div class="notice-card">
  <i class="bi bi-exclamation-triangle notice-icon"></i>
  <div>
    <strong>La extracción es preliminar.</strong>
    <p>La escritura manuscrita y cursiva debe confirmarse manualmente.</p>
  </div>
</div>

<section class="section">
  <div class="review-card">
  {% if payload.fields %}
    <div class="review-stack">
    {% for name, item in payload.fields.items() %}
      <div style="display:grid;grid-template-columns:220px 1fr 80px;gap:12px;align-items:center">
        <strong>{{ name.replace('_',' ')|title }}</strong>
        <input value="{{ item.detected }}" readonly>
        <small>{{ ((item.confidence or 0)*100)|round|int }}%</small>
      </div>
    {% endfor %}
    </div>
  {% else %}
    <p>Aún no se ha ejecutado la extracción por campos.</p>
  {% endif %}
  </div>
</section>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\fields_detected.html"

$patch = @'
from pathlib import Path
import re

p = Path("app/__init__.py")
text = p.read_text(encoding="utf-8")
marker = "app.register_blueprint(fields_bp)"

if marker not in text:
    matches = list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$", text))
    if not matches:
        raise SystemExit("No se encontro return app en app/__init__.py")
    m = matches[-1]
    indent = m.group(1)
    insert = f"{indent}from app.routes.fields import fields_bp\n{indent}app.register_blueprint(fields_bp)\n\n"
    text = text[:m.start()] + insert + text[m.start():]
    p.write_text(text, encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ippliap_ps7_patch.py"
$patch | Set-Content -Encoding UTF8 $tmp
python $tmp
Remove-Item $tmp -Force

Write-Host "PS7 instalado. Ruta: /fields/ID_DEL_CASO" -ForegroundColor Green

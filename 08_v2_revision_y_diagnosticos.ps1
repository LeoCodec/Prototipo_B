param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS8 v2 REVISION HUMANA + DIAGNOSTICOS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

New-Item -ItemType Directory -Force "instance\logs" | Out-Null

@'
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from flask import current_app


def _log_dir() -> Path:
    folder = Path(current_app.instance_path) / "logs"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def record_event(event_type: str, study_id: int | None = None, result: str = "ok") -> None:
    # No guardar nombres, domicilios, telefonos, ingresos ni texto OCR.
    payload = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "event_type": event_type,
        "study_id": study_id,
        "result": result,
    }

    path = _log_dir() / "activity.jsonl"
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(payload, ensure_ascii=False) + "\n")
'@ | Set-Content -Encoding UTF8 "app\services\activity_service.py"

@'
from __future__ import annotations

import os
import traceback
from datetime import datetime
from pathlib import Path
from uuid import uuid4

from flask import current_app, render_template, request
from werkzeug.exceptions import HTTPException


def _log_path() -> Path:
    folder = Path(current_app.instance_path) / "logs"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "prototipo_b_errors.log"


def record_error(exc: Exception) -> str:
    error_id = f"ERR-{datetime.now():%Y%m%d-%H%M%S}-{uuid4().hex[:6].upper()}"

    content = (
        "\n" + "=" * 80 + "\n"
        f"{error_id}\n"
        f"Fecha: {datetime.now().isoformat(timespec='seconds')}\n"
        f"Ruta: {getattr(request, 'method', '?')} {getattr(request, 'path', '?')}\n"
        f"Tipo: {type(exc).__name__}\n"
        f"Mensaje: {exc}\n"
        f"Traceback:\n{traceback.format_exc()}\n"
    )

    with _log_path().open("a", encoding="utf-8") as fh:
        fh.write(content)

    return error_id


def install_error_handler(app):
    @app.errorhandler(Exception)
    def friendly_error(exc):
        if isinstance(exc, HTTPException):
            return exc

        error_id = record_error(exc)
        return render_template("error_friendly.html", error_id=error_id), 500
'@ | Set-Content -Encoding UTF8 "app\services\error_service.py"

@'
from __future__ import annotations

import json
import os
from pathlib import Path

from flask import (
    Blueprint, abort, current_app, flash,
    redirect, render_template, request,
    send_file, url_for
)

from app.models.study import Study
from app.services.activity_service import record_event


review_fields_bp = Blueprint(
    "review_fields",
    __name__,
    url_prefix="/review-fields",
)

diagnostics_bp = Blueprint(
    "diagnostics",
    __name__,
    url_prefix="/diagnostics",
)


def _field_file(study_id: int) -> Path:
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"


def _load(study_id: int) -> dict:
    path = _field_file(study_id)

    if not path.exists():
        return {
            "study_id": study_id,
            "fields": {},
            "context_notes": "",
            "human_reviewed": False,
        }

    return json.loads(path.read_text(encoding="utf-8"))


def _save(study_id: int, payload: dict) -> None:
    _field_file(study_id).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


@review_fields_bp.route("/<int:study_id>", methods=["GET", "POST"])
def review(study_id: int):
    study = Study.query.get_or_404(study_id)
    payload = _load(study_id)

    if request.method == "POST":
        for name, item in payload.get("fields", {}).items():
            value = request.form.get(f"field_{name}", "").strip()
            item["confirmed"] = value

        payload["context_notes"] = request.form.get(
            "context_notes", ""
        ).strip()

        payload["review_notes"] = request.form.get(
            "review_notes", ""
        ).strip()

        payload["human_reviewed"] = True
        _save(study_id, payload)

        record_event("field_review_saved", study.id)
        flash("Revision humana guardada.", "success")

        return redirect(
            url_for("review_fields.review", study_id=study.id)
        )

    return render_template(
        "field_review.html",
        study=study,
        payload=payload,
    )


@diagnostics_bp.get("/health")
def health():
    return {
        "status": "ok",
        "app": "Prototipo B",
        "language": "es",
    }


@diagnostics_bp.get("/errors.txt")
def errors():
    token = os.getenv("DIAGNOSTICS_TOKEN", "")
    supplied = request.args.get("token", "")

    if not current_app.debug and (not token or token != supplied):
        abort(403)

    path = Path(current_app.instance_path) / "logs" / "prototipo_b_errors.log"

    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "Sin errores registrados.\n",
            encoding="utf-8",
        )

    return send_file(
        path,
        as_attachment=True,
        download_name="prototipo_b_errors.txt",
    )
'@ | Set-Content -Encoding UTF8 "app\routes\review_fields.py"

@'
{% extends "base.html" %}
{% block title %}Revisi&oacute;n de campos{% endblock %}
{% block page_name %}Revisi&oacute;n editable{% endblock %}

{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS8 &middot; CONFIRMACI&Oacute;N HUMANA</span>
    <h1>Revisi&oacute;n de campos</h1>
    <p>{{ study.folio }} &middot; {{ study.student_name }}</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-person-check notice-icon"></i>
  <div>
    <strong>OCR detectado no significa dato confirmado.</strong>
    <p>
      Revise especialmente cifras, nombres propios y escritura manuscrita.
    </p>
  </div>
</div>

{% if not payload.fields %}
<section class="section">
  <div class="review-card">
    <p>No hay campos para revisar.</p>
    <a class="btn btn-primary"
       href="{{ url_for('fields.detected', study_id=study.id) }}">
      Volver a extracci&oacute;n
    </a>
  </div>
</section>
{% else %}

<form method="POST">
<section class="section review-stack">
  {% for name, item in payload.fields.items() %}
  <article class="review-card">
    <div class="review-grid">
      <div>
        <span class="eyebrow">DETECTADO</span>
        <h3>{{ item.label or name.replace('_',' ')|title }}</h3>
        <div class="ocr-source">
          {{ item.detected or 'Sin dato detectado' }}
        </div>
        <small>
          Confianza t&eacute;cnica:
          {{ ((item.confidence or 0) * 100)|round|int }}%
        </small>
      </div>

      <div>
        <label>Valor confirmado</label>
        <input
          name="field_{{ name }}"
          value="{{ item.confirmed if item.confirmed is not none else item.detected }}"
          autocomplete="off"
        >
      </div>
    </div>
  </article>
  {% endfor %}

  <article class="review-card">
    <span class="eyebrow">CONTEXTO HUMANO</span>
    <h3>Observaciones del caso</h3>
    <textarea
      name="context_notes"
      rows="5"
      placeholder="Ej. traslado prolongado, empleo irregular, vivienda compartida, informacion aclarada durante la entrevista..."
    >{{ payload.context_notes or '' }}</textarea>
    <small>
      Estas observaciones son registradas por una persona; no son inferencias autom&aacute;ticas.
    </small>
  </article>

  <article class="review-card">
    <span class="eyebrow">CONTROL DEL PILOTO</span>
    <h3>Notas de revisi&oacute;n</h3>
    <textarea
      name="review_notes"
      rows="3"
      placeholder="Ej. OCR confundio dos numeros; se corrigio manualmente."
    >{{ payload.review_notes or '' }}</textarea>
  </article>
</section>

<div class="bottom-actions">
  <a class="btn"
     href="{{ url_for('fields.detected', study_id=study.id) }}">
    Volver
  </a>

  <button class="btn btn-primary" type="submit">
    <i class="bi bi-save"></i> Guardar revisi&oacute;n
  </button>

  {% if payload.human_reviewed %}
  <a class="btn btn-primary"
     href="{{ url_for('analysis.study', study_id=study.id) }}">
    Continuar a indicadores
  </a>
  {% endif %}
</div>
</form>
{% endif %}
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\field_review.html"

@'
{% extends "base.html" %}
{% block title %}Incidencia t&eacute;cnica{% endblock %}
{% block page_name %}Incidencia t&eacute;cnica{% endblock %}

{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PROTOTIPO B</span>
    <h1>No fue posible completar la operaci&oacute;n</h1>
    <p>El sistema registr&oacute; el problema para revisi&oacute;n t&eacute;cnica.</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-tools notice-icon"></i>
  <div>
    <strong>C&oacute;digo de seguimiento: {{ error_id }}</strong>
    <p>
      Puede volver al inicio y continuar con otra tarea.
      El detalle t&eacute;cnico queda en el registro de diagn&oacute;stico.
    </p>
  </div>
</div>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\error_friendly.html"

Write-Host ""
Write-Host "PS8 v2 instalado." -ForegroundColor Green
Write-Host "Revision: /review-fields/ID" -ForegroundColor Cyan
Write-Host "Errores TXT: /diagnostics/errors.txt (debug o token)" -ForegroundColor Cyan

param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS8 - REVISION + DIAGNOSTICOS ===" -ForegroundColor Green

New-Item -ItemType Directory -Force "instance\logs" | Out-Null

@'
from __future__ import annotations

import os
import smtplib
import traceback
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path
from uuid import uuid4

from flask import current_app, request


def log_path():
    folder = Path(current_app.instance_path) / "logs"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / "prototipo_b_errors.log"


def record_error(exc):
    error_id = f"ERR-{datetime.now():%Y%m%d-%H%M%S}-{uuid4().hex[:6].upper()}"
    path = getattr(request, "path", "unknown")
    method = getattr(request, "method", "unknown")

    content = (
        f"\n{'='*80}\n"
        f"{error_id}\n"
        f"Fecha: {datetime.now().isoformat(timespec='seconds')}\n"
        f"Ruta: {method} {path}\n"
        f"Tipo: {type(exc).__name__}\n"
        f"Mensaje: {exc}\n"
        f"Traceback:\n{traceback.format_exc()}\n"
    )

    with log_path().open("a", encoding="utf-8") as fh:
        fh.write(content)

    _optional_email(error_id, type(exc).__name__, str(exc), path)
    return error_id


def _optional_email(error_id, error_type, message, path):
    host = os.getenv("SMTP_HOST")
    user = os.getenv("SMTP_USER")
    password = os.getenv("SMTP_PASSWORD")
    target = os.getenv("ERROR_NOTIFY_TO")

    if not all([host, user, password, target]):
        return

    msg = EmailMessage()
    msg["Subject"] = f"[IPPLIAP Prototipo B] Error {error_id}"
    msg["From"] = user
    msg["To"] = target
    msg.set_content(
        f"Error técnico del Prototipo B.\n\n"
        f"ID: {error_id}\n"
        f"Ruta: {path}\n"
        f"Tipo: {error_type}\n"
        f"Mensaje técnico: {message}\n\n"
        "No se incluyen datos personales del expediente."
    )

    try:
        port = int(os.getenv("SMTP_PORT", "587"))
        with smtplib.SMTP(host, port, timeout=10) as server:
            server.starttls()
            server.login(user, password)
            server.send_message(msg)
    except Exception:
        pass


def install_error_handler(app):
    from flask import render_template
    from werkzeug.exceptions import HTTPException

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
    Blueprint, current_app, request, render_template, redirect, url_for,
    flash, send_file, abort
)

from app.models.study import Study

review_fields_bp = Blueprint("review_fields", __name__, url_prefix="/review-fields")
diagnostics_bp = Blueprint("diagnostics", __name__, url_prefix="/diagnostics")


def _field_file(study_id):
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"


def _load(study_id):
    p = _field_file(study_id)
    if not p.exists():
        return {"study_id": study_id, "fields": {}, "context_notes": ""}
    return json.loads(p.read_text(encoding="utf-8"))


@review_fields_bp.route("/<int:study_id>", methods=["GET", "POST"])
def review(study_id):
    study = Study.query.get_or_404(study_id)
    payload = _load(study_id)

    if request.method == "POST":
        for name, item in payload.get("fields", {}).items():
            item["confirmed"] = request.form.get(f"field_{name}", "").strip()

        payload["context_notes"] = request.form.get("context_notes", "").strip()
        payload["human_reviewed"] = True

        _field_file(study_id).write_text(
            json.dumps(payload, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        flash("Revisión humana guardada.", "success")
        return redirect(url_for("review_fields.review", study_id=study.id))

    return render_template("field_review.html", study=study, payload=payload)


@diagnostics_bp.get("/health")
def health():
    return {"status": "ok", "app": "Prototipo B"}


@diagnostics_bp.get("/errors.txt")
def errors():
    allowed = current_app.debug
    token = os.getenv("DIAGNOSTICS_TOKEN", "")
    supplied = request.args.get("token", "")

    if not allowed and (not token or supplied != token):
        abort(403)

    path = Path(current_app.instance_path) / "logs" / "prototipo_b_errors.log"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("Sin errores registrados.\n", encoding="utf-8")

    return send_file(path, as_attachment=True, download_name="prototipo_b_errors.txt")
'@ | Set-Content -Encoding UTF8 "app\routes\review_fields.py"

@'
{% extends "base.html" %}
{% block title %}Revisión de campos{% endblock %}
{% block page_name %}Revisión editable{% endblock %}
{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS8 · CONFIRMACIÓN HUMANA</span>
    <h1>Revisión de campos</h1>
    <p>{{ study.folio }} · {{ study.student_name }}</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-person-check notice-icon"></i>
  <div>
    <strong>OCR detectado ≠ dato confirmado.</strong>
    <p>Corrija cualquier dato manuscrito antes de exportarlo.</p>
  </div>
</div>

<form method="POST">
<section class="section review-stack">
{% for name, item in payload.fields.items() %}
  <article class="review-card">
    <div class="review-grid">
      <div>
        <span class="eyebrow">DETECTADO</span>
        <h3>{{ name.replace('_',' ')|title }}</h3>
        <div class="ocr-source">{{ item.detected or 'Sin dato detectado' }}</div>
      </div>
      <div>
        <label>Valor confirmado</label>
        <input name="field_{{ name }}" value="{{ item.confirmed or item.detected }}">
      </div>
    </div>
  </article>
{% endfor %}

<article class="review-card">
  <span class="eyebrow">CONTEXTO HUMANO</span>
  <h3>Observaciones de contexto</h3>
  <textarea name="context_notes" rows="5"
    placeholder="Ej. traslado prolongado, situación familiar particular, información aclarada durante la entrevista...">{{ payload.context_notes or '' }}</textarea>
  <small>Este texto lo registra el personal autorizado; no lo genera automáticamente el sistema.</small>
</article>
</section>

<div class="bottom-actions">
  <button class="btn btn-primary" type="submit">
    <i class="bi bi-save"></i> Guardar revisión
  </button>
</div>
</form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\field_review.html"

@'
{% extends "base.html" %}
{% block title %}Error técnico{% endblock %}
{% block page_name %}Incidencia técnica{% endblock %}
{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PROTOTIPO B</span>
    <h1>No fue posible completar esta operación</h1>
    <p>El sistema registró el problema para revisión técnica.</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-tools notice-icon"></i>
  <div>
    <strong>Código de seguimiento: {{ error_id }}</strong>
    <p>Puede volver al inicio. No necesita copiar un traceback técnico.</p>
  </div>
</div>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\error_friendly.html"

$patch = @'
from pathlib import Path
import re

p = Path("app/__init__.py")
text = p.read_text(encoding="utf-8")
matches = list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$", text))
if not matches:
    raise SystemExit("No se encontro return app")

m = matches[-1]
indent = m.group(1)
parts = []

if "app.register_blueprint(review_fields_bp)" not in text:
    parts.append(f"{indent}from app.routes.review_fields import review_fields_bp, diagnostics_bp\n")
    parts.append(f"{indent}app.register_blueprint(review_fields_bp)\n")
    parts.append(f"{indent}app.register_blueprint(diagnostics_bp)\n\n")

if "install_error_handler(app)" not in text:
    parts.append(f"{indent}from app.services.error_service import install_error_handler\n")
    parts.append(f"{indent}install_error_handler(app)\n\n")

if parts:
    text = text[:m.start()] + "".join(parts) + text[m.start():]
    p.write_text(text, encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ippliap_ps8_patch.py"
$patch | Set-Content -Encoding UTF8 $tmp
python $tmp
Remove-Item $tmp -Force

$envExample = ".env.example"
if (-not (Test-Path $envExample)) { New-Item -ItemType File $envExample | Out-Null }
Add-Content $envExample "`n# Diagnosticos"
Add-Content $envExample "DIAGNOSTICS_TOKEN=cambiar-por-un-token-largo"
Add-Content $envExample "# SMTP opcional"
Add-Content $envExample "SMTP_HOST="
Add-Content $envExample "SMTP_PORT=587"
Add-Content $envExample "SMTP_USER="
Add-Content $envExample "SMTP_PASSWORD="
Add-Content $envExample "ERROR_NOTIFY_TO="

Write-Host "PS8 instalado." -ForegroundColor Green
Write-Host "Revisión: /review-fields/ID" -ForegroundColor Cyan
Write-Host "Salud: /diagnostics/health" -ForegroundColor Cyan

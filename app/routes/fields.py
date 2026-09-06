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

from __future__ import annotations

import json
from pathlib import Path

from flask import Blueprint, current_app, render_template, redirect, url_for, flash, request

from app.models.study import Study
from app.services.field_extraction import combine_ocr_text, extract_fields


fields_bp = Blueprint("fields", __name__, url_prefix="/fields")


def _json_path(study_id):
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"


def _load(study_id):
    path = _json_path(study_id)
    if not path.exists():
        return {"study_id": study_id, "fields": {}, "source_text": ""}
    return json.loads(path.read_text(encoding="utf-8"))


def _save(study_id, payload):
    _json_path(study_id).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


@fields_bp.get("/<int:study_id>")
def detected(study_id):
    study = Study.query.get_or_404(study_id)
    return render_template("fields_detected.html", study=study, payload=_load(study_id))


@fields_bp.post("/<int:study_id>/run")
def run(study_id):
    study = Study.query.get_or_404(study_id)
    source_text = combine_ocr_text(study.images)
    fields = extract_fields(source_text)

    payload = {
        "study_id": study.id,
        "folio": study.folio,
        "fields": fields,
        "source_text": source_text,
    }
    _save(study_id, payload)
    flash("Extracción preliminar completada.", "success")
    return redirect(url_for("fields.review", study_id=study.id))


@fields_bp.route("/<int:study_id>/review", methods=["GET", "POST"])
def review(study_id):
    study = Study.query.get_or_404(study_id)
    payload = _load(study_id)

    if request.method == "POST":
        fields = payload.setdefault("fields", {})
        for name in list(fields.keys()):
            confirmed = request.form.get(f"field_{name}", "").strip()
            fields[name]["confirmed"] = confirmed

        payload["human_reviewed"] = True
        _save(study_id, payload)
        flash("Campos confirmados guardados.", "success")
        return redirect(url_for("fields.review", study_id=study.id))

    return render_template("field_review.html", study=study, payload=payload)

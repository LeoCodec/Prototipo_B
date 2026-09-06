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

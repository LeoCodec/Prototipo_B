from __future__ import annotations

from datetime import datetime

from flask import (
    Blueprint, current_app, flash, redirect,
    render_template, request, send_file, url_for
)

from app.models.study import Study
from app.services.activity_service import record_event
from app.services.report_service import (
    bulk_workbook,
    case_workbook,
    safe_name,
)
from app.services.word_report_service import build_case_docx
from app.services.bulk_report_service import build_bulk_workbook


reports_bp = Blueprint("reports", __name__, url_prefix="/reports")


@reports_bp.get("/")
def index():
    studies = Study.query.order_by(Study.id.desc()).all()
    return render_template("reports.html", studies=studies)


@reports_bp.get("/<int:study_id>/excel")
def excel_case(study_id: int):
    study = Study.query.get_or_404(study_id)

    filename = (
        f"{safe_name(study.student_name)}_"
        f"{safe_name(study.folio)}.xlsx"
    )

    output = case_workbook(
        study,
        current_app.instance_path,
    )

    record_event("excel_case_downloaded", study.id)

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "spreadsheetml.sheet"
        ),
    )


@reports_bp.get("/<int:study_id>/word")
def word_case(study_id: int):
    study = Study.query.get_or_404(study_id)

    filename = (
        f"{safe_name(study.student_name)}_"
        f"{safe_name(study.folio)}_justificacion_cuota.docx"
    )

    output = build_case_docx(
        study,
        current_app.instance_path,
    )

    record_event("word_case_downloaded", study.id)

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "wordprocessingml.document"
        ),
    )


@reports_bp.post("/bulk-excel")
def bulk_excel():
    ids = [
        int(value)
        for value in request.form.getlist("study_ids")
        if value.isdigit()
    ]

    if not ids:
        flash("Seleccione al menos un caso.", "warning")
        return redirect(url_for("reports.index"))

    studies = (
        Study.query
        .filter(Study.id.in_(ids))
        .order_by(Study.id.asc())
        .all()
    )

    output = build_bulk_workbook(
        studies,
        current_app.instance_path,
    )

    filename = (
        f"IPPLIAP_Casos_"
        f"{datetime.now():%Y%m%d_%H%M}.xlsx"
    )

    record_event("excel_bulk_downloaded", result=f"{len(studies)} cases")

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "spreadsheetml.sheet"
        ),
    )


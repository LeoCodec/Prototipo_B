from pathlib import Path
from flask import Blueprint, current_app, send_file
from ..models import Study
from ..services.calculations import economic_summary
from ..services.excel_service import build_excel

export_bp = Blueprint("export", __name__, url_prefix="/export")


@export_bp.route("/<int:study_id>/excel")
def excel(study_id):
    study = Study.query.get_or_404(study_id)
    summary = economic_summary(study.total_income, study.total_expenses, study.household_size)
    path = Path(current_app.config["EXPORT_FOLDER"]) / f"{study.folio}.xlsx"
    build_excel(study, path, summary)
    return send_file(path, as_attachment=True, download_name=f"{study.folio}.xlsx")

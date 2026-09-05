from pathlib import Path

from flask import Blueprint, current_app, send_file

from app.models.study import Study
from app.services.excel_service_v2 import build_workbook


export_v2_bp = Blueprint("export_v2", __name__, url_prefix="/export-v2")


@export_v2_bp.get("/<int:study_id>/excel")
def excel(study_id):
    study = Study.query.get_or_404(study_id)

    export_dir = Path(current_app.root_path).parent / "exports"
    export_dir.mkdir(parents=True, exist_ok=True)

    safe_folio = "".join(ch for ch in study.folio if ch.isalnum() or ch in "-_")
    path = export_dir / f"{safe_folio}_prototipo_b.xlsx"

    wb = build_workbook(study, current_app.instance_path)
    wb.save(path)

    return send_file(
        path,
        as_attachment=True,
        download_name=path.name,
        mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    )

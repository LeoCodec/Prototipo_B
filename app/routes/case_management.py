from pathlib import Path
from flask import Blueprint,current_app,flash,redirect,render_template,request,url_for
from app.extensions import db
from app.models.study import Study
from app.services.activity_service import record_event

case_management_bp=Blueprint("case_management",__name__,url_prefix="/cases")

def delete_case(study):
    root=Path(current_app.root_path).parent; uploads=Path(current_app.config.get("UPLOAD_FOLDER") or root/"uploads")
    for image in list(study.images):
        filename=getattr(image,"filename","")
        if filename:
            direct=uploads/filename
            target=direct if direct.exists() else (next(uploads.rglob(filename),None) if uploads.exists() else None)
            if target and target.exists():
                try: target.unlink()
                except OSError: pass
        db.session.delete(image)
    aux=Path(current_app.instance_path)/"field_extractions"/f"study_{study.id}.json"
    if aux.exists():
        try: aux.unlink()
        except OSError: pass
    db.session.delete(study)

@case_management_bp.get("/manage")
def manage(): return render_template("cases_manage.html",studies=Study.query.order_by(Study.id.desc()).all())

@case_management_bp.post("/bulk-delete")
def bulk_delete():
    ids=[int(x) for x in request.form.getlist("study_ids") if x.isdigit()]
    if not ids: flash("Seleccione al menos un caso.","warning"); return redirect(url_for("case_management.manage"))
    studies=Study.query.filter(Study.id.in_(ids)).all()
    for study in studies: record_event("study_deleted",study.id); delete_case(study)
    db.session.commit(); flash(f"Se eliminaron {len(studies)} caso(s) y sus archivos asociados.","success"); return redirect(url_for("case_management.manage"))

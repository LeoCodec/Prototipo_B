from __future__ import annotations
from datetime import datetime
from pathlib import Path
import shutil
from flask import Blueprint,current_app,flash,jsonify,redirect,render_template,request,send_file,url_for
from app.extensions import db
from app.models.study import Study
from app.services.institutional_form_service import delete_form,load_form,save_form
from app.services.institutional_export_service import build_bulk_excel,build_case_excel,build_case_word

institutional_bp=Blueprint("institutional",__name__,url_prefix="/estudios")

def _sync(study,p):
    d=p.get("data",{});c=p.get("calculation",{});parts=[d.get("nombre_alumno",""),d.get("apellido_paterno_alumno",""),d.get("apellido_materno_alumno","")];name=" ".join(str(x).strip() for x in parts if str(x or "").strip())
    if name:study.student_name=name
    if hasattr(study,"total_income"):study.total_income=float(c.get("total_income") or 0)
    if hasattr(study,"total_expenses"):study.total_expenses=float(c.get("total_expenses") or 0)
    if hasattr(study,"household_size"):study.household_size=int(c.get("household_size") or 1)
    if hasattr(study,"final_fee"):study.final_fee=c.get("final_fee")
    study.status="FORMULARIO";db.session.commit()

@institutional_bp.get("/")
def index():
    return render_template("institutional_cases.html",studies=Study.query.order_by(Study.id.desc()).all())

@institutional_bp.post("/nuevo")
def new_case():
    name=(request.form.get("student_name") or "").strip() or "Nuevo estudio";s=Study(folio="ES-"+datetime.now().strftime("%Y%m%d-%H%M%S"),student_name=name,status="FORMULARIO");db.session.add(s);db.session.commit();return redirect(url_for("institutional.form",study_id=s.id))

@institutional_bp.get("/<int:study_id>")
def form(study_id):
    s=Study.query.get_or_404(study_id);return render_template("institutional_form.html",study=s,payload=load_form(current_app.instance_path,study_id))

@institutional_bp.post("/<int:study_id>/guardar")
def save(study_id):
    s=Study.query.get_or_404(study_id);p=save_form(current_app.instance_path,study_id,request.get_json(silent=True) or {});_sync(s,p);return jsonify(ok=True,updated_at=p.get("updated_at"),calculation=p.get("calculation",{}),maps_url=p.get("maps_url",""),maps_static_url=p.get("maps_static_url",""))

@institutional_bp.get("/<int:study_id>/preview")
def preview(study_id):
    s=Study.query.get_or_404(study_id);return render_template("institutional_preview.html",study=s,payload=load_form(current_app.instance_path,study_id))

@institutional_bp.get("/<int:study_id>/excel")
def excel(study_id):
    s=Study.query.get_or_404(study_id);f=build_case_excel(s,current_app.instance_path);return send_file(f,as_attachment=True,download_name=f"{s.folio}_{s.student_name}_estudio.xlsx".replace(" ","_"),mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

@institutional_bp.get("/<int:study_id>/word")
def word(study_id):
    s=Study.query.get_or_404(study_id);f=build_case_word(s,current_app.instance_path);return send_file(f,as_attachment=True,download_name=f"{s.folio}_{s.student_name}_estudio.docx".replace(" ","_"),mimetype="application/vnd.openxmlformats-officedocument.wordprocessingml.document")

@institutional_bp.post("/exportar/excel")
def bulk_excel():
    ids=[]
    for v in request.form.getlist("study_ids"):
        try:ids.append(int(v))
        except:pass
    if not ids:flash("Seleccione al menos un caso.","warning");return redirect(url_for("institutional.index"))
    studies=Study.query.filter(Study.id.in_(ids)).order_by(Study.id.asc()).all();f=build_bulk_excel(studies,current_app.instance_path);return send_file(f,as_attachment=True,download_name="IPPLIAP_Estudios_"+datetime.now().strftime("%Y%m%d_%H%M")+".xlsx",mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

@institutional_bp.post("/<int:study_id>/eliminar")
def delete(study_id):
    s=Study.query.get_or_404(study_id);delete_form(current_app.instance_path,study_id)
    for p in (Path(current_app.instance_path)/"field_extractions"/f"study_{study_id}.json",Path(current_app.instance_path)/"analysis"/f"study_{study_id}.json"):
        if p.exists():p.unlink()
    db.session.delete(s);db.session.commit();flash("Caso eliminado.","success");return redirect(url_for("institutional.index"))

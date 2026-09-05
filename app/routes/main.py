from datetime import datetime
from flask import Blueprint, render_template, request, redirect, url_for
from ..extensions import db
from ..models import Study

main_bp = Blueprint("main", __name__)


@main_bp.route("/")
def index():
    studies = Study.query.order_by(Study.created_at.desc()).all()
    return render_template("index.html", studies=studies)


@main_bp.route("/studies/new", methods=["POST"])
def new_study():
    name = request.form.get("student_name", "").strip()
    folio = "PB-" + datetime.now().strftime("%Y%m%d-%H%M%S")
    study = Study(folio=folio, student_name=name, status="CAPTURA")
    db.session.add(study)
    db.session.commit()
    return redirect(url_for("capture.mobile_capture", study_id=study.id))


@main_bp.route("/studies/<int:study_id>")
def study_detail(study_id):
    study = Study.query.get_or_404(study_id)
    return render_template("study_detail.html", study=study)

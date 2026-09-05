from flask import Blueprint, render_template, request, redirect, url_for, flash
from ..extensions import db
from ..models import Study, StudyImage
from ..services.calculations import economic_summary

review_bp = Blueprint("review", __name__, url_prefix="/review")


@review_bp.route("/<int:study_id>", methods=["GET", "POST"])
def review_study(study_id):
    study = Study.query.get_or_404(study_id)

    if request.method == "POST":
        study.total_income = float(request.form.get("total_income") or 0)
        study.total_expenses = float(request.form.get("total_expenses") or 0)
        study.household_size = max(int(request.form.get("household_size") or 1), 1)
        fee = request.form.get("final_fee", "").strip()
        study.final_fee = float(fee) if fee else None
        study.status = "REVISIÓN"

        for image in study.images:
            image.confirmed_text = request.form.get(f"confirmed_{image.id}", image.ocr_text)

        db.session.commit()
        flash("Revisión guardada.", "success")
        return redirect(url_for("review.review_study", study_id=study.id))

    summary = economic_summary(study.total_income, study.total_expenses, study.household_size)
    return render_template("review.html", study=study, summary=summary)

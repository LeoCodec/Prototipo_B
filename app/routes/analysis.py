from flask import Blueprint, render_template, request, redirect, url_for, flash

from app.extensions import db
from app.models.study import Study
from app.services.socioeconomic_metrics import calculate_metrics


analysis_bp = Blueprint("analysis", __name__, url_prefix="/analysis")


@analysis_bp.route("/<int:study_id>", methods=["GET", "POST"])
def study(study_id):
    case = Study.query.get_or_404(study_id)

    if request.method == "POST":
        case.total_income = float(request.form.get("total_income") or 0)
        case.total_expenses = float(request.form.get("total_expenses") or 0)
        case.household_size = max(int(request.form.get("household_size") or 1), 1)

        final_fee_raw = (request.form.get("final_fee") or "").strip()
        if final_fee_raw:
            case.final_fee = float(final_fee_raw)

        db.session.commit()
        flash("Datos económicos actualizados.", "success")
        return redirect(url_for("analysis.study", study_id=case.id))

    metrics = calculate_metrics(
        case.total_income or 0,
        case.total_expenses or 0,
        case.household_size or 1,
    )

    return render_template("analysis.html", study=case, metrics=metrics)

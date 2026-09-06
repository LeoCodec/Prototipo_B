from __future__ import annotations

import json
from pathlib import Path

from flask import (
    Blueprint, current_app, flash, redirect,
    render_template, request, url_for
)

from app.extensions import db
from app.models.study import Study
from app.services.activity_service import record_event
from app.services.socioeconomic_metrics import (
    calculate_metrics,
    descriptive_findings,
    parse_money,
)


analysis_bp = Blueprint("analysis", __name__, url_prefix="/analysis")
case_tools_bp = Blueprint("case_tools", __name__, url_prefix="/case-tools")


EXPENSE_FIELDS = [
    "predial", "renta", "luz", "agua", "telefono_gasto",
    "gas", "alimentos", "automovil", "pasajes", "colegiaturas",
    "vestido", "medico_medicinas", "muebles_hogar",
    "creditos_personales", "otros_gastos",
]


def _field_file(study_id: int) -> Path:
    folder = Path(current_app.instance_path) / "field_extractions"
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"study_{study_id}.json"


def _load_payload(study_id: int) -> dict:
    path = _field_file(study_id)
    if not path.exists():
        return {"fields": {}, "analysis": {}, "context_notes": ""}
    return json.loads(path.read_text(encoding="utf-8"))


def _save_payload(study_id: int, payload: dict) -> None:
    _field_file(study_id).write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _confirmed(payload: dict, name: str):
    item = payload.get("fields", {}).get(name, {})
    return item.get("confirmed") or item.get("detected") or ""


def _initial_values(study, payload):
    analysis = payload.get("analysis", {})

    income = analysis.get("total_income")
    if income is None:
        income = getattr(study, "total_income", None)
    if not income:
        income = parse_money(_confirmed(payload, "total_ingresos"))

    expenses = analysis.get("total_expenses")
    if expenses is None:
        expenses = getattr(study, "total_expenses", None)
    if not expenses:
        expenses = sum(
            parse_money(_confirmed(payload, name))
            for name in EXPENSE_FIELDS
        )

    household_size = (
        analysis.get("household_size")
        or getattr(study, "household_size", None)
        or 1
    )

    final_fee = analysis.get("final_fee")
    if final_fee is None:
        final_fee = getattr(study, "final_fee", None)

    return income or 0, expenses or 0, household_size, final_fee


@analysis_bp.route("/<int:study_id>", methods=["GET", "POST"])
def study(study_id: int):
    case = Study.query.get_or_404(study_id)
    payload = _load_payload(study_id)

    income, expenses, household_size, final_fee = _initial_values(
        case, payload
    )

    if request.method == "POST":
        income = parse_money(request.form.get("total_income"))
        expenses = parse_money(request.form.get("total_expenses"))

        try:
            household_size = max(
                int(request.form.get("household_size") or 1),
                1,
            )
        except ValueError:
            household_size = 1

        raw_fee = (request.form.get("final_fee") or "").strip()
        final_fee = parse_money(raw_fee) if raw_fee else None

        payload["analysis"] = {
            "total_income": income,
            "total_expenses": expenses,
            "household_size": household_size,
            "final_fee": final_fee,
        }
        _save_payload(study_id, payload)

        # Mantener compatibilidad con el modelo actual si las columnas existen.
        for attr, value in [
            ("total_income", income),
            ("total_expenses", expenses),
            ("household_size", household_size),
            ("final_fee", final_fee),
        ]:
            if hasattr(case, attr):
                setattr(case, attr, value)

        db.session.commit()
        record_event("analysis_saved", case.id)

        flash("Indicadores recalculados y guardados.", "success")
        return redirect(url_for("analysis.study", study_id=case.id))

    metrics = calculate_metrics(income, expenses, household_size)

    return render_template(
        "analysis.html",
        study=case,
        metrics=metrics,
        findings=descriptive_findings(metrics),
        final_fee=final_fee,
    )


@case_tools_bp.post("/<int:study_id>/delete")
def delete(study_id: int):
    study = Study.query.get_or_404(study_id)

    if request.form.get("confirm") != "ELIMINAR":
        flash(
            "El caso no se elimino. Falta la confirmacion ELIMINAR.",
            "warning",
        )
        return redirect(url_for("main.index"))

    project_root = Path(current_app.root_path).parent
    upload_root = Path(
        current_app.config.get("UPLOAD_FOLDER")
        or project_root / "uploads"
    )

    for image in list(study.images):
        filename = getattr(image, "filename", "")

        if filename:
            path = upload_root / filename
            if not path.exists() and upload_root.exists():
                path = next(upload_root.rglob(filename), path)

            if path.exists():
                try:
                    path.unlink()
                except OSError:
                    pass

        db.session.delete(image)

    aux = _field_file(study.id)
    if aux.exists():
        try:
            aux.unlink()
        except OSError:
            pass

    record_event("study_deleted", study.id)
    db.session.delete(study)
    db.session.commit()

    flash("Caso eliminado junto con sus archivos asociados.", "success")
    return redirect(url_for("main.index"))

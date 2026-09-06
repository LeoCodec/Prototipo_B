param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS9 v2 INDICADORES + GESTION DE CASOS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

@'
from __future__ import annotations

import re
from dataclasses import asdict, dataclass


@dataclass
class Metrics:
    total_income: float
    total_expenses: float
    household_size: int
    available: float
    income_per_capita: float
    available_per_capita: float
    expense_burden_pct: float

    def as_dict(self):
        return asdict(self)


def parse_money(value) -> float:
    if value is None:
        return 0.0

    if isinstance(value, (int, float)):
        return float(value)

    text = str(value).strip()
    if not text:
        return 0.0

    # Acepta $ 1,250.50 o 1250
    text = re.sub(r"[^\d,.\-]", "", text)

    if "," in text and "." not in text:
        # En estos formatos, la coma suele ser separador de miles.
        text = text.replace(",", "")
    else:
        text = text.replace(",", "")

    try:
        return float(text)
    except ValueError:
        return 0.0


def calculate_metrics(total_income, total_expenses, household_size):
    income = max(parse_money(total_income), 0.0)
    expenses = max(parse_money(total_expenses), 0.0)

    try:
        n = int(household_size or 1)
    except (TypeError, ValueError):
        n = 1

    n = max(n, 1)

    available = income - expenses
    income_per_capita = income / n
    available_per_capita = available / n
    burden = (expenses / income * 100.0) if income > 0 else 0.0

    return Metrics(
        total_income=round(income, 2),
        total_expenses=round(expenses, 2),
        household_size=n,
        available=round(available, 2),
        income_per_capita=round(income_per_capita, 2),
        available_per_capita=round(available_per_capita, 2),
        expense_burden_pct=round(burden, 2),
    )


def descriptive_findings(metrics: Metrics) -> list[str]:
    findings = []

    if metrics.total_income == 0 and metrics.total_expenses > 0:
        findings.append(
            "Hay gastos registrados y el ingreso total es cero; "
            "conviene revisar la captura o confirmacion."
        )

    if metrics.total_income > 0:
        findings.append(
            f"El gasto registrado representa "
            f"{metrics.expense_burden_pct:.2f}% del ingreso mensual."
        )

    if metrics.available < 0:
        findings.append(
            "Los gastos registrados superan al ingreso mensual registrado."
        )
    elif metrics.available >= 0:
        findings.append(
            f"El disponible mensual calculado es "
            f"${metrics.available:,.2f}."
        )

    findings.append(
        f"El ingreso mensual per capita calculado es "
        f"${metrics.income_per_capita:,.2f}."
    )

    return findings
'@ | Set-Content -Encoding UTF8 "app\services\socioeconomic_metrics.py"

@'
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
'@ | Set-Content -Encoding UTF8 "app\routes\analysis_tools.py"

@'
{% extends "base.html" %}
{% block title %}Indicadores socioecon&oacute;micos{% endblock %}
{% block page_name %}Indicadores socioecon&oacute;micos{% endblock %}

{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS9 &middot; AN&Aacute;LISIS DESCRIPTIVO</span>
    <h1>Resumen econ&oacute;mico</h1>
    <p>{{ study.folio }} &middot; {{ study.student_name }}</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-person-check notice-icon"></i>
  <div>
    <strong>El sistema calcula indicadores, no una cuota autom&aacute;tica.</strong>
    <p>La cuota final permanece bajo valoraci&oacute;n del personal autorizado.</p>
  </div>
</div>

<form method="POST">
<section class="section work-grid">
  <article class="module-card">
    <span class="eyebrow">DATOS CONFIRMADOS</span>
    <h2>Entradas econ&oacute;micas</h2>

    <label>Ingreso total mensual</label>
    <input
      name="total_income"
      type="number"
      min="0"
      step="0.01"
      value="{{ metrics.total_income }}"
    >

    <label style="margin-top:12px">Gasto total mensual</label>
    <input
      name="total_expenses"
      type="number"
      min="0"
      step="0.01"
      value="{{ metrics.total_expenses }}"
    >

    <label style="margin-top:12px">Integrantes del hogar</label>
    <input
      name="household_size"
      type="number"
      min="1"
      value="{{ metrics.household_size }}"
    >
  </article>

  <article class="module-card module-card-soft">
    <span class="eyebrow">VALORACI&Oacute;N HUMANA</span>
    <h2>Cuota final autorizada</h2>
    <label>Cuota final</label>
    <input
      name="final_fee"
      type="number"
      min="0"
      step="0.01"
      value="{{ final_fee if final_fee is not none else '' }}"
    >
    <small>
      El sistema no recomienda ni autoriza esta cantidad.
    </small>
  </article>
</section>

<section class="quality-dashboard">
  <article class="quality-stat">
    <span>Disponible</span>
    <strong>${{ "{:,.2f}".format(metrics.available) }}</strong>
    <small>IT - GT</small>
  </article>

  <article class="quality-stat green">
    <span>Ingreso per c&aacute;pita</span>
    <strong>${{ "{:,.2f}".format(metrics.income_per_capita) }}</strong>
    <small>IT / N</small>
  </article>

  <article class="quality-stat yellow">
    <span>Disponible per c&aacute;pita</span>
    <strong>${{ "{:,.2f}".format(metrics.available_per_capita) }}</strong>
    <small>(IT - GT) / N</small>
  </article>

  <article class="quality-stat red">
    <span>Carga de gasto</span>
    <strong>{{ metrics.expense_burden_pct }}%</strong>
    <small>GT / IT x 100</small>
  </article>
</section>

<section class="section">
  <article class="review-card">
    <span class="eyebrow">LECTURA DESCRIPTIVA</span>
    <h2>Hallazgos del c&aacute;lculo</h2>
    <ul>
      {% for item in findings %}
      <li>{{ item }}</li>
      {% endfor %}
    </ul>
  </article>
</section>

<div class="bottom-actions">
  <a class="btn"
     href="{{ url_for('review_fields.review', study_id=study.id) }}">
    Volver a revisi&oacute;n
  </a>

  <button class="btn btn-primary" type="submit">
    <i class="bi bi-save"></i> Guardar y recalcular
  </button>

  <a class="btn btn-primary"
     href="{{ url_for('reports.index') }}">
    Ir a reportes
  </a>
</div>
</form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\analysis.html"

# Test matematico independiente.
New-Item -ItemType Directory -Force "tests" | Out-Null
@'
import unittest

from app.services.socioeconomic_metrics import calculate_metrics


class MetricsTest(unittest.TestCase):
    def test_standard_case(self):
        m = calculate_metrics(10000, 7000, 4)
        self.assertEqual(m.available, 3000.0)
        self.assertEqual(m.income_per_capita, 2500.0)
        self.assertEqual(m.available_per_capita, 750.0)
        self.assertEqual(m.expense_burden_pct, 70.0)

    def test_zero_income(self):
        m = calculate_metrics(0, 500, 2)
        self.assertEqual(m.expense_burden_pct, 0.0)
        self.assertEqual(m.available, -500.0)

    def test_household_floor(self):
        m = calculate_metrics(9000, 3000, 0)
        self.assertEqual(m.household_size, 1)


if __name__ == "__main__":
    unittest.main()
'@ | Set-Content -Encoding UTF8 "tests\test_socioeconomic_metrics.py"

& $Py -m unittest tests.test_socioeconomic_metrics -v

Write-Host ""
Write-Host "PS9 v2 instalado y formulas probadas." -ForegroundColor Green

param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS9 - CALCULOS Y GESTION ===" -ForegroundColor Green

@'
from dataclasses import dataclass, asdict


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


def calculate_metrics(total_income, total_expenses, household_size):
    income = max(float(total_income or 0), 0.0)
    expenses = max(float(total_expenses or 0), 0.0)
    n = max(int(household_size or 1), 1)

    available = income - expenses
    ipc = income / n
    dpc = available / n
    burden = (expenses / income * 100.0) if income > 0 else 0.0

    return Metrics(
        total_income=round(income, 2),
        total_expenses=round(expenses, 2),
        household_size=n,
        available=round(available, 2),
        income_per_capita=round(ipc, 2),
        available_per_capita=round(dpc, 2),
        expense_burden_pct=round(burden, 2),
    )
'@ | Set-Content -Encoding UTF8 "app\services\socioeconomic_metrics.py"

@'
from pathlib import Path

from flask import Blueprint, current_app, render_template, request, redirect, url_for, flash

from app.extensions import db
from app.models.study import Study
from app.services.socioeconomic_metrics import calculate_metrics

analysis_bp = Blueprint("analysis", __name__, url_prefix="/analysis")
case_tools_bp = Blueprint("case_tools", __name__, url_prefix="/case-tools")


@analysis_bp.route("/<int:study_id>", methods=["GET", "POST"])
def study(study_id):
    case = Study.query.get_or_404(study_id)

    if request.method == "POST":
        case.total_income = float(request.form.get("total_income") or 0)
        case.total_expenses = float(request.form.get("total_expenses") or 0)
        case.household_size = max(int(request.form.get("household_size") or 1), 1)

        raw_fee = (request.form.get("final_fee") or "").strip()
        case.final_fee = float(raw_fee) if raw_fee else None

        db.session.commit()
        flash("Indicadores recalculados.", "success")
        return redirect(url_for("analysis.study", study_id=case.id))

    metrics = calculate_metrics(case.total_income, case.total_expenses, case.household_size)
    return render_template("analysis.html", study=case, metrics=metrics)


@case_tools_bp.post("/<int:study_id>/delete")
def delete(study_id):
    study = Study.query.get_or_404(study_id)

    if request.form.get("confirm") != "ELIMINAR":
        flash("El caso no se eliminó. Falta la confirmación.", "warning")
        return redirect(url_for("main.index"))

    upload_root = Path(current_app.root_path).parent / "uploads"

    for image in list(study.images):
        filename = getattr(image, "filename", "")
        if filename:
            path = upload_root / filename
            if path.exists():
                try:
                    path.unlink()
                except OSError:
                    pass
        db.session.delete(image)

    aux = Path(current_app.instance_path) / "field_extractions" / f"study_{study.id}.json"
    if aux.exists():
        try:
            aux.unlink()
        except OSError:
            pass

    db.session.delete(study)
    db.session.commit()

    flash(f"Caso {study.folio} eliminado.", "success")
    return redirect(url_for("main.index"))
'@ | Set-Content -Encoding UTF8 "app\routes\analysis_tools.py"

@'
{% extends "base.html" %}
{% block title %}Resumen económico{% endblock %}
{% block page_name %}Indicadores socioeconómicos{% endblock %}
{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS9 · ANÁLISIS DESCRIPTIVO</span>
    <h1>Resumen económico</h1>
    <p>{{ study.folio }} · {{ study.student_name }}</p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-person-check notice-icon"></i>
  <div>
    <strong>Estos cálculos describen el caso.</strong>
    <p>No asignan automáticamente una cuota.</p>
  </div>
</div>

<form method="POST">
<section class="section work-grid">
  <article class="module-card">
    <h2>Datos económicos</h2>
    <label>Ingreso total mensual</label>
    <input name="total_income" type="number" min="0" step="0.01" value="{{ study.total_income or 0 }}">

    <label style="margin-top:12px">Gasto total mensual</label>
    <input name="total_expenses" type="number" min="0" step="0.01" value="{{ study.total_expenses or 0 }}">

    <label style="margin-top:12px">Integrantes del hogar</label>
    <input name="household_size" type="number" min="1" value="{{ study.household_size or 1 }}">
  </article>

  <article class="module-card module-card-soft">
    <h2>Cuota final autorizada</h2>
    <label>Cuota final</label>
    <input name="final_fee" type="number" min="0" step="0.01"
      value="{{ study.final_fee if study.final_fee is not none else '' }}">
  </article>
</section>

<section class="quality-dashboard">
  <article class="quality-stat"><span>Disponible</span><strong>${{ "{:,.2f}".format(metrics.available) }}</strong><small>IT − GT</small></article>
  <article class="quality-stat green"><span>Ingreso per cápita</span><strong>${{ "{:,.2f}".format(metrics.income_per_capita) }}</strong><small>IT / N</small></article>
  <article class="quality-stat yellow"><span>Disponible per cápita</span><strong>${{ "{:,.2f}".format(metrics.available_per_capita) }}</strong><small>(IT − GT) / N</small></article>
  <article class="quality-stat red"><span>Carga de gasto</span><strong>{{ metrics.expense_burden_pct }}%</strong><small>GT / IT × 100</small></article>
</section>

<div class="bottom-actions">
  <button class="btn btn-primary" type="submit"><i class="bi bi-save"></i> Guardar y recalcular</button>
</div>
</form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\analysis.html"

$patch = @'
from pathlib import Path
import re

p = Path("app/__init__.py")
text = p.read_text(encoding="utf-8")
marker = "app.register_blueprint(analysis_bp)"

if marker not in text:
    matches = list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$", text))
    if not matches:
        raise SystemExit("No se encontro return app")
    m = matches[-1]
    indent = m.group(1)
    insert = (
        f"{indent}from app.routes.analysis_tools import analysis_bp, case_tools_bp\n"
        f"{indent}app.register_blueprint(analysis_bp)\n"
        f"{indent}app.register_blueprint(case_tools_bp)\n\n"
    )
    text = text[:m.start()] + insert + text[m.start():]
    p.write_text(text, encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ippliap_ps9_patch.py"
$patch | Set-Content -Encoding UTF8 $tmp
python $tmp
Remove-Item $tmp -Force

Write-Host "PS9 instalado. Ruta: /analysis/ID" -ForegroundColor Green

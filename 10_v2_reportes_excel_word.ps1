param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS10 v2 EXCEL + WORD + EXPORTACION MULTIPLE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

if (-not (Select-String -Path "requirements.txt" -Pattern '^\s*openpyxl\b' -Quiet)) {
    Add-Content "requirements.txt" "`nopenpyxl>=3.1"
}
if (-not (Select-String -Path "requirements.txt" -Pattern '^\s*python-docx\b' -Quiet)) {
    Add-Content "requirements.txt" "`npython-docx>=1.1"
}

& $Py -m pip install -r requirements.txt

@'
from __future__ import annotations

import json
import re
from io import BytesIO
from pathlib import Path

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from app.services.socioeconomic_metrics import (
    calculate_metrics,
    descriptive_findings,
)


DARK = "315500"
WHITE = "FFFFFF"


def safe_name(value: str) -> str:
    value = re.sub(r'[\\/:*?"<>|]+', "_", value or "caso")
    value = re.sub(r"\s+", "_", value).strip("._")
    return value[:80] or "caso"


def field_payload(instance_path: str, study_id: int) -> dict:
    path = (
        Path(instance_path)
        / "field_extractions"
        / f"study_{study_id}.json"
    )

    if not path.exists():
        return {
            "fields": {},
            "context_notes": "",
            "review_notes": "",
            "analysis": {},
        }

    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {
            "fields": {},
            "context_notes": "",
            "review_notes": "",
            "analysis": {},
        }


def _metric_values(study, payload):
    analysis = payload.get("analysis", {})

    income = analysis.get(
        "total_income",
        getattr(study, "total_income", 0) or 0,
    )
    expenses = analysis.get(
        "total_expenses",
        getattr(study, "total_expenses", 0) or 0,
    )
    household = analysis.get(
        "household_size",
        getattr(study, "household_size", 1) or 1,
    )
    final_fee = analysis.get(
        "final_fee",
        getattr(study, "final_fee", None),
    )

    return (
        calculate_metrics(income, expenses, household),
        final_fee,
    )


def _header(cell):
    cell.fill = PatternFill("solid", fgColor=DARK)
    cell.font = Font(color=WHITE, bold=True)
    cell.alignment = Alignment(horizontal="center")


def _autowidth(ws, max_width=55):
    for cells in ws.columns:
        index = cells[0].column
        size = max(len(str(cell.value or "")) for cell in cells)
        ws.column_dimensions[get_column_letter(index)].width = min(
            max(size + 2, 10),
            max_width,
        )


def case_workbook(study, instance_path: str) -> BytesIO:
    payload = field_payload(instance_path, study.id)
    metrics, final_fee = _metric_values(study, payload)

    wb = Workbook()

    # 1. Resumen
    ws = wb.active
    ws.title = "Resumen"

    ws["A1"] = "IPPLIAP - Prototipo B - Resumen del expediente"
    ws["A1"].font = Font(size=16, bold=True, color=DARK)
    ws.merge_cells("A1:D1")

    rows = [
        ("Folio", study.folio),
        ("Caso", study.student_name),
        ("Estatus", study.status),
        ("Ingreso total", metrics.total_income),
        ("Gasto total", metrics.total_expenses),
        ("Disponible", metrics.available),
        ("Integrantes del hogar", metrics.household_size),
        ("Ingreso per capita", metrics.income_per_capita),
        ("Disponible per capita", metrics.available_per_capita),
        ("Carga de gasto (%)", metrics.expense_burden_pct),
        ("Cuota final autorizada", final_fee if final_fee is not None else ""),
        ("Observaciones de contexto", payload.get("context_notes", "")),
        ("Notas de revision", payload.get("review_notes", "")),
    ]

    for row_index, (label, value) in enumerate(rows, start=3):
        ws.cell(row_index, 1, label).font = Font(
            bold=True,
            color=DARK,
        )
        ws.cell(row_index, 2, value)

    # Grafico simple y descriptivo.
    base = 18
    ws.cell(base, 1, "Indicador")
    ws.cell(base, 2, "Monto")
    _header(ws.cell(base, 1))
    _header(ws.cell(base, 2))

    chart_rows = [
        ("Ingreso", metrics.total_income),
        ("Gasto", metrics.total_expenses),
        ("Disponible", metrics.available),
    ]
    for row_index, values in enumerate(chart_rows, start=base + 1):
        ws.cell(row_index, 1, values[0])
        ws.cell(row_index, 2, values[1])

    chart = BarChart()
    chart.title = "Resumen economico"
    data = Reference(
        ws,
        min_col=2,
        min_row=base,
        max_row=base + len(chart_rows),
    )
    categories = Reference(
        ws,
        min_col=1,
        min_row=base + 1,
        max_row=base + len(chart_rows),
    )
    chart.add_data(data, titles_from_data=True)
    chart.set_categories(categories)
    ws.add_chart(chart, "D18")

    # 2. Campos confirmados
    fields_ws = wb.create_sheet("Campos_confirmados")
    for col, title in enumerate(
        ["Campo", "Detectado", "Confirmado", "Confianza"],
        start=1,
    ):
        fields_ws.cell(1, col, title)
        _header(fields_ws.cell(1, col))

    for row_index, (name, item) in enumerate(
        payload.get("fields", {}).items(),
        start=2,
    ):
        fields_ws.cell(
            row_index,
            1,
            item.get("label") or name,
        )
        fields_ws.cell(row_index, 2, item.get("detected", ""))
        fields_ws.cell(row_index, 3, item.get("confirmed", ""))
        fields_ws.cell(
            row_index,
            4,
            round(float(item.get("confidence", 0)) * 100, 2),
        )

    # 3. OCR por pagina
    ocr_ws = wb.create_sheet("OCR_por_pagina")
    for col, title in enumerate(
        ["Pagina", "Archivo", "Calidad", "Texto OCR", "Texto confirmado", "Error OCR"],
        start=1,
    ):
        ocr_ws.cell(1, col, title)
        _header(ocr_ws.cell(1, col))

    for row_index, image in enumerate(study.images, start=2):
        values = [
            image.page_number,
            image.filename,
            image.quality_status,
            image.ocr_text or "",
            image.confirmed_text or "",
            image.ocr_error or "",
        ]

        for col, value in enumerate(values, start=1):
            ocr_ws.cell(row_index, col, value)

        ocr_ws.cell(row_index, 4).alignment = Alignment(
            wrap_text=True,
            vertical="top",
        )
        ocr_ws.cell(row_index, 5).alignment = Alignment(
            wrap_text=True,
            vertical="top",
        )

    # 4. Indicadores
    ind_ws = wb.create_sheet("Indicadores")
    indicators = [
        ("Ingreso total", metrics.total_income, "IT"),
        ("Gasto total", metrics.total_expenses, "GT"),
        ("Disponible", metrics.available, "IT - GT"),
        ("Ingreso per capita", metrics.income_per_capita, "IT / N"),
        ("Disponible per capita", metrics.available_per_capita, "(IT - GT) / N"),
        ("Carga de gasto (%)", metrics.expense_burden_pct, "(GT / IT) x 100"),
    ]

    for col, title in enumerate(["Indicador", "Resultado", "Formula"], start=1):
        ind_ws.cell(1, col, title)
        _header(ind_ws.cell(1, col))

    for row_index, values in enumerate(indicators, start=2):
        for col, value in enumerate(values, start=1):
            ind_ws.cell(row_index, col, value)

    # 5. Hallazgos descriptivos
    findings_ws = wb.create_sheet("Lectura_descriptiva")
    findings_ws["A1"] = "Hallazgos descriptivos"
    _header(findings_ws["A1"])
    findings_ws["B1"] = "Nota"
    _header(findings_ws["B1"])

    for row_index, item in enumerate(
        descriptive_findings(metrics),
        start=2,
    ):
        findings_ws.cell(row_index, 1, row_index - 1)
        findings_ws.cell(row_index, 2, item)

    for sheet in wb.worksheets:
        sheet.freeze_panes = "A2"
        _autowidth(sheet)

    output = BytesIO()
    wb.save(output)
    output.seek(0)
    return output


def bulk_workbook(studies, instance_path: str) -> BytesIO:
    wb = Workbook()
    ws = wb.active
    ws.title = "Resumen_general"

    headers = [
        "Folio",
        "Caso",
        "Estatus",
        "Ingreso total",
        "Gasto total",
        "Disponible",
        "Integrantes",
        "Ingreso per capita",
        "Disponible per capita",
        "Carga de gasto (%)",
        "Cuota final autorizada",
        "Contexto humano",
    ]

    for col, title in enumerate(headers, start=1):
        ws.cell(1, col, title)
        _header(ws.cell(1, col))

    for row_index, study in enumerate(studies, start=2):
        payload = field_payload(instance_path, study.id)
        metrics, final_fee = _metric_values(study, payload)

        values = [
            study.folio,
            study.student_name,
            study.status,
            metrics.total_income,
            metrics.total_expenses,
            metrics.available,
            metrics.household_size,
            metrics.income_per_capita,
            metrics.available_per_capita,
            metrics.expense_burden_pct,
            final_fee if final_fee is not None else "",
            payload.get("context_notes", ""),
        ]

        for col, value in enumerate(values, start=1):
            ws.cell(row_index, col, value)

    _autowidth(ws)
    ws.freeze_panes = "A2"

    output = BytesIO()
    wb.save(output)
    output.seek(0)
    return output
'@ | Set-Content -Encoding UTF8 "app\services\report_service.py"

@'
from __future__ import annotations

from io import BytesIO

from docx import Document
from docx.shared import Pt

from app.services.report_service import field_payload
from app.services.socioeconomic_metrics import (
    calculate_metrics,
    descriptive_findings,
)


def build_case_docx(study, instance_path: str) -> BytesIO:
    payload = field_payload(instance_path, study.id)
    analysis = payload.get("analysis", {})

    income = analysis.get(
        "total_income",
        getattr(study, "total_income", 0) or 0,
    )
    expenses = analysis.get(
        "total_expenses",
        getattr(study, "total_expenses", 0) or 0,
    )
    household = analysis.get(
        "household_size",
        getattr(study, "household_size", 1) or 1,
    )
    final_fee = analysis.get(
        "final_fee",
        getattr(study, "final_fee", None),
    )

    metrics = calculate_metrics(
        income,
        expenses,
        household,
    )

    doc = Document()
    doc.styles["Normal"].font.name = "Aptos"
    doc.styles["Normal"].font.size = Pt(10)

    doc.add_heading("IPPLIAP - Prototipo B", level=1)
    doc.add_paragraph(
        "Resumen de digitalizacion del estudio socioeconomico"
    )

    doc.add_heading("Identificacion del expediente", level=2)
    table = doc.add_table(rows=0, cols=2)
    table.style = "Table Grid"

    identification = [
        ("Folio", study.folio),
        ("Caso", study.student_name),
        ("Estatus", study.status),
    ]

    for label, value in identification:
        cells = table.add_row().cells
        cells[0].text = str(label)
        cells[1].text = str(value or "")

    doc.add_heading("Campos confirmados", level=2)
    confirmed_table = doc.add_table(rows=1, cols=3)
    confirmed_table.style = "Table Grid"
    confirmed_table.rows[0].cells[0].text = "Campo"
    confirmed_table.rows[0].cells[1].text = "Detectado"
    confirmed_table.rows[0].cells[2].text = "Confirmado"

    for name, item in payload.get("fields", {}).items():
        cells = confirmed_table.add_row().cells
        cells[0].text = str(item.get("label") or name)
        cells[1].text = str(item.get("detected") or "")
        cells[2].text = str(item.get("confirmed") or "")

    doc.add_heading("Indicadores descriptivos", level=2)
    metric_table = doc.add_table(rows=0, cols=2)
    metric_table.style = "Table Grid"

    metric_rows = [
        ("Ingreso total", f"${metrics.total_income:,.2f}"),
        ("Gasto total", f"${metrics.total_expenses:,.2f}"),
        ("Disponible", f"${metrics.available:,.2f}"),
        ("Integrantes del hogar", str(metrics.household_size)),
        ("Ingreso per capita", f"${metrics.income_per_capita:,.2f}"),
        ("Disponible per capita", f"${metrics.available_per_capita:,.2f}"),
        ("Carga de gasto", f"{metrics.expense_burden_pct:.2f}%"),
        (
            "Cuota final autorizada",
            "" if final_fee is None else f"${float(final_fee):,.2f}",
        ),
    ]

    for label, value in metric_rows:
        cells = metric_table.add_row().cells
        cells[0].text = label
        cells[1].text = value

    doc.add_heading("Lectura descriptiva", level=2)
    for finding in descriptive_findings(metrics):
        doc.add_paragraph(finding, style="List Bullet")

    doc.add_heading("Observaciones de contexto", level=2)
    doc.add_paragraph(
        payload.get("context_notes")
        or "Sin observaciones adicionales registradas."
    )

    doc.add_heading("Notas de revision del piloto", level=2)
    doc.add_paragraph(
        payload.get("review_notes")
        or "Sin notas adicionales de revision."
    )

    doc.add_heading("Alcance de la salida", level=2)
    doc.add_paragraph(
        "El OCR y los indicadores son herramientas de apoyo. "
        "La informacion manuscrita debe ser revisada por una persona "
        "y la cuota final no se determina automaticamente."
    )

    output = BytesIO()
    doc.save(output)
    output.seek(0)
    return output
'@ | Set-Content -Encoding UTF8 "app\services\word_report_service.py"

@'
from __future__ import annotations

from datetime import datetime

from flask import (
    Blueprint, current_app, flash, redirect,
    render_template, request, send_file, url_for
)

from app.models.study import Study
from app.services.activity_service import record_event
from app.services.report_service import (
    bulk_workbook,
    case_workbook,
    safe_name,
)
from app.services.word_report_service import build_case_docx


reports_bp = Blueprint("reports", __name__, url_prefix="/reports")


@reports_bp.get("/")
def index():
    studies = Study.query.order_by(Study.id.desc()).all()
    return render_template("reports.html", studies=studies)


@reports_bp.get("/<int:study_id>/excel")
def excel_case(study_id: int):
    study = Study.query.get_or_404(study_id)

    filename = (
        f"{safe_name(study.student_name)}_"
        f"{safe_name(study.folio)}.xlsx"
    )

    output = case_workbook(
        study,
        current_app.instance_path,
    )

    record_event("excel_case_downloaded", study.id)

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "spreadsheetml.sheet"
        ),
    )


@reports_bp.get("/<int:study_id>/word")
def word_case(study_id: int):
    study = Study.query.get_or_404(study_id)

    filename = (
        f"{safe_name(study.student_name)}_"
        f"{safe_name(study.folio)}_resumen.docx"
    )

    output = build_case_docx(
        study,
        current_app.instance_path,
    )

    record_event("word_case_downloaded", study.id)

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "wordprocessingml.document"
        ),
    )


@reports_bp.post("/bulk-excel")
def bulk_excel():
    ids = [
        int(value)
        for value in request.form.getlist("study_ids")
        if value.isdigit()
    ]

    if not ids:
        flash("Seleccione al menos un caso.", "warning")
        return redirect(url_for("reports.index"))

    studies = (
        Study.query
        .filter(Study.id.in_(ids))
        .order_by(Study.id.asc())
        .all()
    )

    output = bulk_workbook(
        studies,
        current_app.instance_path,
    )

    filename = (
        f"IPPLIAP_Casos_"
        f"{datetime.now():%Y%m%d_%H%M}.xlsx"
    )

    record_event("excel_bulk_downloaded", result=f"{len(studies)} cases")

    return send_file(
        output,
        as_attachment=True,
        download_name=filename,
        mimetype=(
            "application/vnd.openxmlformats-officedocument."
            "spreadsheetml.sheet"
        ),
    )
'@ | Set-Content -Encoding UTF8 "app\routes\reports.py"

@'
{% extends "base.html" %}
{% block title %}Reportes{% endblock %}
{% block page_name %}Reportes y exportaci&oacute;n{% endblock %}

{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS10 &middot; SALIDAS</span>
    <h1>Reportes del Prototipo B</h1>
    <p>
      Genere Excel o Word por expediente, o consolide varios casos en un mismo Excel.
    </p>
  </div>
</section>

<div class="notice-card">
  <i class="bi bi-file-earmark-check notice-icon"></i>
  <div>
    <strong>Los reportes se generan en memoria.</strong>
    <p>
      No se acumulan copias de Excel o Word en el servidor despu&eacute;s de cada descarga.
    </p>
  </div>
</div>

<form method="POST" action="{{ url_for('reports.bulk_excel') }}">
<section class="section">
  <div class="review-card">
    <div class="bottom-actions" style="justify-content:flex-end;margin-bottom:15px">
      <button class="btn btn-primary" type="submit">
        <i class="bi bi-file-earmark-excel"></i>
        Excel de seleccionados
      </button>
    </div>

    <div style="overflow:auto">
      <table style="width:100%;border-collapse:collapse">
        <thead>
          <tr>
            <th style="width:60px">Elegir</th>
            <th>Folio</th>
            <th>Caso</th>
            <th>Estatus</th>
            <th>Acciones</th>
          </tr>
        </thead>

        <tbody>
        {% for study in studies %}
          <tr>
            <td>
              <input
                type="checkbox"
                name="study_ids"
                value="{{ study.id }}"
              >
            </td>
            <td>{{ study.folio }}</td>
            <td>{{ study.student_name }}</td>
            <td>{{ study.status }}</td>
            <td>
              <a
                class="btn"
                href="{{ url_for('reports.excel_case', study_id=study.id) }}"
              >
                Excel
              </a>

              <a
                class="btn"
                href="{{ url_for('reports.word_case', study_id=study.id) }}"
              >
                Word
              </a>

              <a
                class="btn"
                href="{{ url_for('analysis.study', study_id=study.id) }}"
              >
                Indicadores
              </a>
            </td>
          </tr>
        {% else %}
          <tr>
            <td colspan="5">No hay casos registrados.</td>
          </tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</section>
</form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\reports.html"

Write-Host ""
Write-Host "PS10 v2 instalado." -ForegroundColor Green
Write-Host "Reportes: http://127.0.0.1:5000/reports/" -ForegroundColor Cyan
Write-Host "Los Excel/Word se generan en memoria; no llenan exports/." -ForegroundColor Cyan

param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS10 - REPORTES, EXCEL Y LOTE ===" -ForegroundColor Green

$req = "requirements.txt"
if (-not (Test-Path $req)) { New-Item -ItemType File $req | Out-Null }
$txt = Get-Content $req -Raw

foreach ($pkg in @("openpyxl>=3.1","python-docx>=1.1")) {
    $name = ($pkg -split "[><=]")[0]
    if ($txt -notmatch "(?im)^$([regex]::Escape($name))") {
        Add-Content $req $pkg
    }
}

@'
from __future__ import annotations

import json
import re
from pathlib import Path

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter

from app.services.socioeconomic_metrics import calculate_metrics


DARK = "315500"
WHITE = "FFFFFF"


def safe_name(value):
    value = re.sub(r'[\\/:*?"<>|]+', "_", value or "caso")
    value = re.sub(r"\s+", "_", value).strip("._")
    return value[:80] or "caso"


def field_payload(instance_path, study_id):
    p = Path(instance_path) / "field_extractions" / f"study_{study_id}.json"
    if not p.exists():
        return {"fields": {}, "context_notes": ""}
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return {"fields": {}, "context_notes": ""}


def _header(cell):
    cell.fill = PatternFill("solid", fgColor=DARK)
    cell.font = Font(color=WHITE, bold=True)
    cell.alignment = Alignment(horizontal="center")


def _width(ws, max_width=50):
    for cells in ws.columns:
        idx = cells[0].column
        length = max(len(str(c.value or "")) for c in cells)
        ws.column_dimensions[get_column_letter(idx)].width = min(max(length + 2, 10), max_width)


def case_workbook(study, instance_path):
    wb = Workbook()
    ws = wb.active
    ws.title = "Resumen"

    metrics = calculate_metrics(study.total_income, study.total_expenses, study.household_size)
    payload = field_payload(instance_path, study.id)

    ws["A1"] = "IPPLIAP · Prototipo B · Resumen del expediente"
    ws["A1"].font = Font(size=16, bold=True, color=DARK)
    ws.merge_cells("A1:D1")

    summary = [
        ("Folio", study.folio),
        ("Caso", study.student_name),
        ("Estatus", study.status),
        ("Ingreso total", metrics.total_income),
        ("Gasto total", metrics.total_expenses),
        ("Disponible", metrics.available),
        ("Integrantes", metrics.household_size),
        ("Ingreso per cápita", metrics.income_per_capita),
        ("Disponible per cápita", metrics.available_per_capita),
        ("Carga de gasto (%)", metrics.expense_burden_pct),
        ("Cuota final autorizada", study.final_fee if study.final_fee is not None else ""),
        ("Observaciones de contexto", payload.get("context_notes", "")),
    ]

    for r, (label, value) in enumerate(summary, start=3):
        ws.cell(r, 1, label).font = Font(bold=True, color=DARK)
        ws.cell(r, 2, value)

    base = 17
    ws.cell(base, 1, "Indicador")
    ws.cell(base, 2, "Monto")
    _header(ws.cell(base,1))
    _header(ws.cell(base,2))

    for i, row in enumerate([
        ("Ingreso", metrics.total_income),
        ("Gasto", metrics.total_expenses),
        ("Disponible", metrics.available),
    ], start=base+1):
        ws.cell(i,1,row[0])
        ws.cell(i,2,row[1])

    chart = BarChart()
    chart.title = "Resumen económico"
    data = Reference(ws, min_col=2, min_row=base, max_row=base+3)
    cats = Reference(ws, min_col=1, min_row=base+1, max_row=base+3)
    chart.add_data(data, titles_from_data=True)
    chart.set_categories(cats)
    ws.add_chart(chart, "D17")

    pages = wb.create_sheet("Paginas")
    for c, h in enumerate(["Página","Archivo","Calidad","Enfoque","Brillo","Error OCR"],1):
        pages.cell(1,c,h)
        _header(pages.cell(1,c))
    for r, image in enumerate(study.images,2):
        vals = [
            image.page_number, image.filename, image.quality_status,
            image.blur_score, image.brightness_score, image.ocr_error or ""
        ]
        for c,v in enumerate(vals,1):
            pages.cell(r,c,v)

    ocr = wb.create_sheet("OCR")
    for c,h in enumerate(["Página","Texto OCR","Texto confirmado"],1):
        ocr.cell(1,c,h)
        _header(ocr.cell(1,c))
    for r,image in enumerate(study.images,2):
        ocr.cell(r,1,image.page_number)
        ocr.cell(r,2,image.ocr_text or "")
        ocr.cell(r,3,image.confirmed_text or "")
        ocr.cell(r,2).alignment = Alignment(wrap_text=True, vertical="top")
        ocr.cell(r,3).alignment = Alignment(wrap_text=True, vertical="top")

    fields = wb.create_sheet("Campos_confirmados")
    for c,h in enumerate(["Campo","Detectado","Confirmado","Confianza"],1):
        fields.cell(1,c,h)
        _header(fields.cell(1,c))

    for r,(name,item) in enumerate(payload.get("fields",{}).items(),2):
        fields.cell(r,1,name)
        fields.cell(r,2,item.get("detected",""))
        fields.cell(r,3,item.get("confirmed",""))
        fields.cell(r,4,item.get("confidence",0))

    for sheet in wb.worksheets:
        sheet.freeze_panes = "A2"
        _width(sheet)

    return wb


def bulk_workbook(studies, instance_path):
    wb = Workbook()
    ws = wb.active
    ws.title = "Resumen_general"

    headers = [
        "Folio","Caso","Estatus","Ingreso total","Gasto total","Disponible",
        "Integrantes","Ingreso per cápita","Disponible per cápita",
        "Carga de gasto (%)","Cuota final autorizada","Contexto"
    ]

    for c,h in enumerate(headers,1):
        ws.cell(1,c,h)
        _header(ws.cell(1,c))

    for r, study in enumerate(studies,2):
        m = calculate_metrics(study.total_income, study.total_expenses, study.household_size)
        payload = field_payload(instance_path, study.id)
        vals = [
            study.folio, study.student_name, study.status,
            m.total_income, m.total_expenses, m.available, m.household_size,
            m.income_per_capita, m.available_per_capita, m.expense_burden_pct,
            study.final_fee if study.final_fee is not None else "",
            payload.get("context_notes","")
        ]
        for c,v in enumerate(vals,1):
            ws.cell(r,c,v)

    _width(ws)
    ws.freeze_panes = "A2"
    return wb
'@ | Set-Content -Encoding UTF8 "app\services\report_service.py"

@'
from pathlib import Path

from docx import Document
from docx.shared import Pt

from app.services.socioeconomic_metrics import calculate_metrics
from app.services.report_service import field_payload


def build_case_docx(study, instance_path, output_path):
    m = calculate_metrics(study.total_income, study.total_expenses, study.household_size)
    payload = field_payload(instance_path, study.id)

    doc = Document()
    doc.styles["Normal"].font.name = "Aptos"
    doc.styles["Normal"].font.size = Pt(10)

    doc.add_heading("IPPLIAP · Prototipo B", level=1)
    doc.add_paragraph("Resumen técnico del expediente socioeconómico")

    table = doc.add_table(rows=0, cols=2)
    table.style = "Table Grid"

    rows = [
        ("Folio", study.folio),
        ("Caso", study.student_name),
        ("Estatus", study.status),
        ("Ingreso total", f"${m.total_income:,.2f}"),
        ("Gasto total", f"${m.total_expenses:,.2f}"),
        ("Disponible", f"${m.available:,.2f}"),
        ("Integrantes", str(m.household_size)),
        ("Ingreso per cápita", f"${m.income_per_capita:,.2f}"),
        ("Disponible per cápita", f"${m.available_per_capita:,.2f}"),
        ("Carga de gasto", f"{m.expense_burden_pct:.2f}%"),
        ("Cuota final autorizada", "" if study.final_fee is None else f"${study.final_fee:,.2f}"),
    ]

    for label, value in rows:
        cells = table.add_row().cells
        cells[0].text = label
        cells[1].text = value

    doc.add_heading("Observaciones de contexto", level=2)
    doc.add_paragraph(payload.get("context_notes") or "Sin observaciones adicionales registradas.")

    doc.add_heading("Nota de interpretación", level=2)
    doc.add_paragraph(
        "Los indicadores son descriptivos y sirven como apoyo. "
        "La valoración y la cuota final permanecen bajo responsabilidad del personal autorizado."
    )

    doc.save(output_path)
    return output_path
'@ | Set-Content -Encoding UTF8 "app\services\word_report_service.py"

@'
from datetime import datetime
from pathlib import Path

from flask import Blueprint, current_app, render_template, request, send_file, redirect, url_for, flash

from app.models.study import Study
from app.services.report_service import safe_name, case_workbook, bulk_workbook
from app.services.word_report_service import build_case_docx


reports_bp = Blueprint("reports", __name__, url_prefix="/reports")


def _dir():
    p = Path(current_app.root_path).parent / "exports"
    p.mkdir(parents=True, exist_ok=True)
    return p


@reports_bp.get("/")
def index():
    studies = Study.query.order_by(Study.id.desc()).all()
    return render_template("reports.html", studies=studies)


@reports_bp.get("/<int:study_id>/excel")
def excel_case(study_id):
    study = Study.query.get_or_404(study_id)
    filename = f"{safe_name(study.student_name)}_{safe_name(study.folio)}.xlsx"
    path = _dir() / filename
    wb = case_workbook(study, current_app.instance_path)
    wb.save(path)
    return send_file(path, as_attachment=True, download_name=filename)


@reports_bp.get("/<int:study_id>/word")
def word_case(study_id):
    study = Study.query.get_or_404(study_id)
    filename = f"{safe_name(study.student_name)}_{safe_name(study.folio)}_resumen.docx"
    path = _dir() / filename
    build_case_docx(study, current_app.instance_path, path)
    return send_file(path, as_attachment=True, download_name=filename)


@reports_bp.post("/bulk-excel")
def bulk_excel():
    ids = [int(x) for x in request.form.getlist("study_ids") if x.isdigit()]

    if not ids:
        flash("Seleccione al menos un caso.", "warning")
        return redirect(url_for("reports.index"))

    studies = Study.query.filter(Study.id.in_(ids)).order_by(Study.id.asc()).all()
    filename = f"IPPLIAP_Casos_{datetime.now():%Y%m%d_%H%M}.xlsx"
    path = _dir() / filename

    wb = bulk_workbook(studies, current_app.instance_path)
    wb.save(path)

    return send_file(path, as_attachment=True, download_name=filename)
'@ | Set-Content -Encoding UTF8 "app\routes\reports.py"

@'
{% extends "base.html" %}
{% block title %}Reportes{% endblock %}
{% block page_name %}Reportes y exportación{% endblock %}
{% block content %}
<section class="page-title-card">
  <div>
    <span class="eyebrow">PS10 · SALIDAS</span>
    <h1>Reportes del Prototipo B</h1>
    <p>Exportación individual o conjunta de casos confirmados.</p>
  </div>
</section>

<form method="POST" action="{{ url_for('reports.bulk_excel') }}">
<section class="section">
  <div class="review-card">
    <div class="bottom-actions" style="justify-content:flex-end;margin-bottom:15px">
      <button class="btn btn-primary" type="submit">
        <i class="bi bi-file-earmark-excel"></i> Excel de seleccionados
      </button>
    </div>

    <div style="overflow:auto">
      <table style="width:100%;border-collapse:collapse">
        <thead>
          <tr>
            <th></th>
            <th>Folio</th>
            <th>Caso</th>
            <th>Estatus</th>
            <th>Acciones</th>
          </tr>
        </thead>
        <tbody>
        {% for study in studies %}
          <tr>
            <td><input type="checkbox" name="study_ids" value="{{ study.id }}"></td>
            <td>{{ study.folio }}</td>
            <td>{{ study.student_name }}</td>
            <td>{{ study.status }}</td>
            <td>
              <a class="btn" href="{{ url_for('reports.excel_case', study_id=study.id) }}">Excel</a>
              <a class="btn" href="{{ url_for('reports.word_case', study_id=study.id) }}">Word</a>
              <a class="btn" href="{{ url_for('analysis.study', study_id=study.id) }}">Análisis</a>
            </td>
          </tr>
        {% else %}
          <tr><td colspan="5">No hay casos registrados.</td></tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</section>
</form>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\reports.html"

$patch = @'
from pathlib import Path
import re

p = Path("app/__init__.py")
text = p.read_text(encoding="utf-8")
marker = "app.register_blueprint(reports_bp)"

if marker not in text:
    matches = list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$", text))
    if not matches:
        raise SystemExit("No se encontro return app")
    m = matches[-1]
    indent = m.group(1)
    insert = f"{indent}from app.routes.reports import reports_bp\n{indent}app.register_blueprint(reports_bp)\n\n"
    text = text[:m.start()] + insert + text[m.start():]
    p.write_text(text, encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ippliap_ps10_patch.py"
$patch | Set-Content -Encoding UTF8 $tmp
python $tmp
Remove-Item $tmp -Force

Write-Host "PS10 instalado." -ForegroundColor Green
Write-Host "Ejecute: pip install -r requirements.txt" -ForegroundColor Yellow
Write-Host "Reportes: /reports/" -ForegroundColor Cyan

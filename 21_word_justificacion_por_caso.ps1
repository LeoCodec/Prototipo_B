param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"

if (-not (Test-Path $Py)) { throw "No se encontro el Python del venv." }
if ((git branch --show-current).Trim() -ne "main") { throw "PS21 debe ejecutarse solamente en main." }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS21 WORD DE JUSTIFICACION POR CASO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupRoot = Join-Path $ProjectPath "backup_ps21_$stamp"
New-Item -ItemType Directory -Force $backupRoot | Out-Null

foreach ($file in @(
    "app\services\word_report_service.py",
    "app\routes\reports.py",
    "app\templates\study_detail.html"
)) {
    if (Test-Path $file) {
        $dest = Join-Path $backupRoot $file
        New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
        Copy-Item $file $dest -Force
    }
}

Write-Host "Backup: $backupRoot" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1] Actualizando Word de justificacion" -ForegroundColor Cyan

@'
from __future__ import annotations

from io import BytesIO
from urllib.parse import quote_plus

from docx import Document
from docx.enum.text import WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt

from app.services.report_service import field_payload
from app.services.socioeconomic_metrics import calculate_metrics


LABELS = {
    "grado_solicita": "Grado que solicita",
    "turno": "Turno",
    "fecha_entrevista": "Fecha de entrevista",
    "nombre_alumno": "Nombre del alumno",
    "edad": "Edad",
    "fecha_nacimiento": "Fecha de nacimiento",
    "telefono": "Teléfono",
    "domicilio": "Domicilio",
    "codigo_postal": "Código postal",
    "total_ingresos": "Total de ingresos",
    "predial": "Predial",
    "renta": "Renta",
    "luz": "Luz",
    "agua": "Agua",
    "telefono_gasto": "Teléfono (gasto)",
    "gas": "Gas",
    "alimentos": "Alimentos",
    "automovil": "Automóvil",
    "pasajes": "Pasajes",
    "colegiaturas": "Colegiaturas",
    "vestido": "Vestido",
    "medico_medicinas": "Médico y medicinas",
    "muebles_hogar": "Muebles del hogar",
    "creditos_personales": "Créditos personales",
    "otros_gastos": "Otros gastos",
    "servicio_medico": "Servicio médico",
    "enfermedades_cronicas": "Enfermedades crónicas",
    "tiempo_libre": "Tiempo libre",
    "referencias": "Referencias",
    "observaciones": "Observaciones",
}

SECTIONS = [
    (
        "1. Datos generales del alumno",
        [
            "grado_solicita",
            "turno",
            "fecha_entrevista",
            "nombre_alumno",
            "edad",
            "fecha_nacimiento",
            "telefono",
        ],
    ),
    (
        "2. Vivienda y localización",
        [
            "domicilio",
            "codigo_postal",
        ],
    ),
    (
        "3. Ingresos y egresos del hogar",
        [
            "total_ingresos",
            "predial",
            "renta",
            "luz",
            "agua",
            "telefono_gasto",
            "gas",
            "alimentos",
            "automovil",
            "pasajes",
            "colegiaturas",
            "vestido",
            "medico_medicinas",
            "muebles_hogar",
            "creditos_personales",
            "otros_gastos",
        ],
    ),
    (
        "4. Salud y condiciones relevantes",
        [
            "servicio_medico",
            "enfermedades_cronicas",
            "tiempo_libre",
            "referencias",
            "observaciones",
        ],
    ),
]


def _confirmed(payload, key):
    item = payload.get("fields", {}).get(key, {})
    return item.get("confirmed") or item.get("detected") or ""


def _maps_url(payload):
    address = _confirmed(payload, "domicilio").strip()
    postal_code = _confirmed(payload, "codigo_postal").strip()
    query = ", ".join(part for part in (address, postal_code) if part)
    if not query:
        return ""
    return "https://www.google.com/maps/search/?api=1&query=" + quote_plus(query)


def _analysis(study, payload):
    data = payload.get("analysis", {})
    income = data.get("total_income", getattr(study, "total_income", 0) or 0)
    expenses = data.get("total_expenses", getattr(study, "total_expenses", 0) or 0)
    household = data.get("household_size", getattr(study, "household_size", 1) or 1)
    final_fee = data.get("final_fee", getattr(study, "final_fee", None))
    return calculate_metrics(income, expenses, household), final_fee


def _money(value):
    try:
        return f"$ {float(value):,.2f} MXN"
    except (TypeError, ValueError):
        return "—"


def _add_hyperlink(paragraph, text, url):
    part = paragraph.part
    relationship_id = part.relate_to(
        url,
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
        is_external=True,
    )
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), relationship_id)
    run = OxmlElement("w:r")
    properties = OxmlElement("w:rPr")
    color = OxmlElement("w:color")
    color.set(qn("w:val"), "0563C1")
    properties.append(color)
    underline = OxmlElement("w:u")
    underline.set(qn("w:val"), "single")
    properties.append(underline)
    run.append(properties)
    text_element = OxmlElement("w:t")
    text_element.text = text
    run.append(text_element)
    hyperlink.append(run)
    paragraph._p.append(hyperlink)


def _add_field_table(doc, payload, keys):
    rows = []
    for key in keys:
        value = _confirmed(payload, key)
        if value not in (None, ""):
            rows.append((LABELS.get(key, key.replace("_", " ").title()), str(value)))
    if not rows:
        doc.add_paragraph("Sin información confirmada en esta sección.")
        return
    table = doc.add_table(rows=1, cols=2)
    table.style = "Table Grid"
    header = table.rows[0].cells
    header[0].text = "Campo"
    header[1].text = "Dato confirmado"
    for label, value in rows:
        cells = table.add_row().cells
        cells[0].text = label
        cells[1].text = value


def _expense_summary(payload):
    keys = [
        "predial", "renta", "luz", "agua", "telefono_gasto", "gas",
        "alimentos", "automovil", "pasajes", "colegiaturas", "vestido",
        "medico_medicinas", "muebles_hogar", "creditos_personales", "otros_gastos",
    ]
    items = []
    for key in keys:
        value = _confirmed(payload, key)
        if value not in (None, "", "Ninguno", "Ninguna", "No aplica", "No"):
            items.append(f"{LABELS.get(key, key)}: {value}")
    return items


def _descriptive_reading(payload, metrics, final_fee):
    paragraphs = []
    paragraphs.append(
        "El presente documento resume únicamente la información confirmada durante la revisión del expediente."
    )
    paragraphs.append(
        "El hogar fue registrado con "
        f"{metrics.household_size} integrante(s). "
        f"El ingreso total considerado es {_money(metrics.total_income)} y el gasto total considerado es {_money(metrics.total_expenses)}."
    )
    paragraphs.append(
        "El disponible calculado después de los gastos registrados es "
        f"{_money(metrics.available)}. El ingreso per cápita es {_money(metrics.income_per_capita)} "
        f"y el disponible per cápita es {_money(metrics.available_per_capita)}."
    )
    if metrics.expense_burden_pct is not None:
        paragraphs.append(
            "La proporción de gasto registrada equivale a "
            f"{float(metrics.expense_burden_pct):.2f} % del ingreso considerado."
        )
    expenses = _expense_summary(payload)
    if expenses:
        paragraphs.append(
            "Entre los egresos o compromisos confirmados se encuentran: " + "; ".join(expenses) + "."
        )
    health = []
    for key in ("servicio_medico", "enfermedades_cronicas", "medico_medicinas"):
        value = _confirmed(payload, key)
        if value not in (None, "", "Ninguno", "Ninguna", "No aplica", "No"):
            health.append(f"{LABELS.get(key, key)}: {value}")
    if health:
        paragraphs.append("En materia de salud se documentó: " + "; ".join(health) + ".")
    observations = _confirmed(payload, "observaciones")
    if observations:
        paragraphs.append("Las observaciones confirmadas del expediente señalan: " + str(observations))
    context_notes = str(payload.get("context_notes", "") or "").strip()
    if context_notes:
        paragraphs.append(
            "Contexto familiar y socioeconómico registrado por la persona revisora: " + context_notes
        )
    if final_fee not in (None, ""):
        paragraphs.append(
            "La cuota final registrada para este expediente es "
            f"{_money(final_fee)}. Esta cantidad debe interpretarse junto con los datos confirmados, "
            "los indicadores y el contexto familiar documentado."
        )
    else:
        paragraphs.append(
            "La cuota final aún no ha sido autorizada. El documento puede utilizarse como apoyo para la revisión institucional antes de registrar una cuota."
        )
    return paragraphs


def build_case_docx(study, instance_path):
    payload = field_payload(instance_path, study.id)
    metrics, final_fee = _analysis(study, payload)
    doc = Document()
    styles = doc.styles
    styles["Normal"].font.name = "Arial"
    styles["Normal"].font.size = Pt(10)

    doc.add_heading("Resumen y justificación del estudio socioeconómico", level=0)
    doc.add_paragraph(
        f"Folio: {study.folio}\n"
        f"Caso: {study.student_name}\n"
        f"Estatus: {study.status}"
    )

    for title, keys in SECTIONS:
        doc.add_heading(title, level=1)
        _add_field_table(doc, payload, keys)
        if title.startswith("2."):
            maps_url = _maps_url(payload)
            if maps_url:
                paragraph = doc.add_paragraph()
                paragraph.add_run("Ubicación de referencia: ").bold = True
                _add_hyperlink(paragraph, "Abrir en Google Maps", maps_url)

    doc.add_heading("5. Contexto familiar y circunstancias particulares", level=1)
    context_notes = str(payload.get("context_notes", "") or "").strip()
    review_notes = str(payload.get("review_notes", "") or "").strip()
    if context_notes:
        doc.add_paragraph(context_notes)
    else:
        doc.add_paragraph("Sin notas de contexto familiar confirmadas.")
    if review_notes:
        doc.add_heading("Notas de revisión", level=2)
        doc.add_paragraph(review_notes)

    doc.add_heading("6. Indicadores socioeconómicos", level=1)
    indicators = [
        ("Ingreso total", _money(metrics.total_income)),
        ("Gasto total", _money(metrics.total_expenses)),
        ("Disponible", _money(metrics.available)),
        ("Integrantes del hogar", str(metrics.household_size)),
        ("Ingreso per cápita", _money(metrics.income_per_capita)),
        ("Disponible per cápita", _money(metrics.available_per_capita)),
        (
            "Carga de gasto",
            f"{float(metrics.expense_burden_pct):.2f} %" if metrics.expense_burden_pct is not None else "—",
        ),
    ]
    table = doc.add_table(rows=1, cols=2)
    table.style = "Table Grid"
    table.rows[0].cells[0].text = "Indicador"
    table.rows[0].cells[1].text = "Resultado"
    for label, value in indicators:
        cells = table.add_row().cells
        cells[0].text = label
        cells[1].text = value

    doc.add_heading("7. Lectura descriptiva del caso", level=1)
    for paragraph_text in _descriptive_reading(payload, metrics, final_fee):
        doc.add_paragraph(paragraph_text)

    doc.add_heading("8. Cuota y fundamento documental", level=1)
    fee_table = doc.add_table(rows=1, cols=2)
    fee_table.style = "Table Grid"
    fee_table.rows[0].cells[0].text = "Concepto"
    fee_table.rows[0].cells[1].text = "Resultado"

    row = fee_table.add_row().cells
    row[0].text = "Cuota sugerida automática"
    row[1].text = "No aplicada en el Prototipo B"

    row = fee_table.add_row().cells
    row[0].text = "Cuota final autorizada"
    row[1].text = _money(final_fee) if final_fee not in (None, "") else "Pendiente"

    doc.add_paragraph(
        "El sistema organiza información, calcula indicadores y genera una lectura descriptiva como apoyo a la valoración. "
        "No asigna automáticamente una cuota vinculante. La cuota final corresponde a la decisión del personal institucional autorizado, "
        "considerando también circunstancias familiares que pueden no quedar representadas por una fórmula."
    )

    doc.add_paragraph(
        "Ejemplos de circunstancias que deben quedar registradas en las notas de contexto cuando correspondan: separación de los padres, "
        "aportaciones parciales, hogares monoparentales, apoyo de abuelos u otros familiares, ingresos irregulares, becas, gastos médicos "
        "y cualquier otra situación relevante para la valoración."
    )

    doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)
    doc.add_heading("9. Alcance del documento", level=1)
    doc.add_paragraph(
        "Este documento es un resumen de apoyo derivado de la información capturada y confirmada en el expediente. "
        "No sustituye el estudio físico, la entrevista, la observación profesional ni la decisión final del personal responsable de IPPLIAP."
    )

    output = BytesIO()
    doc.save(output)
    output.seek(0)
    return output
'@ | Set-Content -Encoding UTF8 "app\services\word_report_service.py"

Write-Host ""
Write-Host "[2] Ajustando nombre del Word descargable" -ForegroundColor Cyan

$reports = "app\routes\reports.py"
$reportsText = Get-Content $reports -Raw -Encoding UTF8
$reportsText = $reportsText.Replace("_resumen.docx", "_justificacion_cuota.docx")
Set-Content -Path $reports -Value $reportsText -Encoding UTF8

Write-Host ""
Write-Host "[3] Agregando Word al detalle de cada caso" -ForegroundColor Cyan

$patchTemplate = Join-Path $ProjectPath "_tmp_ps21_template.py"

@'
from pathlib import Path

path = Path("app/templates/study_detail.html")
text = path.read_text(encoding="utf-8")

marker = "<!-- PS12-FLUJO -->"
endblock = "{% endblock %}"

start = text.find(marker)
if start == -1:
    raise SystemExit("No se encontro el marcador PS12-FLUJO.")

end = text.rfind(endblock)
if end == -1 or end < start:
    raise SystemExit("No se encontro el endblock final.")

replacement = '''<!-- PS12-FLUJO -->
<section class="section">
    <article class="review-card">
        <span class="eyebrow">FLUJO DEL EXPEDIENTE</span>
        <h2>Continuar procesamiento</h2>
        <p>
            Revise los campos, confirme la información y genere los documentos
            del expediente cuando la revisión esté lista.
        </p>
        <div class="bottom-actions">
            <a class="btn btn-primary"
               href="{{ url_for('fields.detected', study_id=study.id) }}">
                <i class="bi bi-ui-checks-grid"></i>
                Extracción por campos
            </a>
            <a class="btn"
               href="{{ url_for('review_fields.review', study_id=study.id) }}">
                <i class="bi bi-pencil-square"></i>
                Revisión confirmada
            </a>
            <a class="btn"
               href="{{ url_for('analysis.study', study_id=study.id) }}">
                <i class="bi bi-calculator"></i>
                Indicadores
            </a>
        </div>
    </article>
</section>

<section class="section">
    <article class="review-card">
        <span class="eyebrow">DOCUMENTOS DEL EXPEDIENTE</span>
        <h2>Exportar caso</h2>
        <p>
            El Excel conserva los datos del expediente. El Word presenta
            el resumen, los indicadores, el contexto y el fundamento
            documental de la cuota final registrada.
        </p>
        <div class="bottom-actions">
            <a class="btn"
               href="{{ url_for('reports.excel_case', study_id=study.id) }}">
                <i class="bi bi-file-earmark-excel"></i>
                Excel del caso
            </a>
            <a class="btn btn-primary"
               href="{{ url_for('reports.word_case', study_id=study.id) }}">
                <i class="bi bi-file-earmark-word"></i>
                Word - Justificación de cuota
            </a>
        </div>
    </article>
</section>

'''

updated = text[:start] + replacement + text[end:]
path.write_text(updated, encoding="utf-8")
print("study_detail.html actualizado.")
'@ | Set-Content -Encoding UTF8 $patchTemplate

& $Py $patchTemplate
$patchCode = $LASTEXITCODE
Remove-Item $patchTemplate -Force -ErrorAction SilentlyContinue
if ($patchCode -ne 0) { throw "Fallo el parche de study_detail.html." }

Write-Host ""
Write-Host "[4] Validando PS21" -ForegroundColor Cyan

& $Py -m compileall app -q
if ($LASTEXITCODE -ne 0) { throw "Fallo compileall." }

& $Py -c "from app import create_app; a=create_app(); print('OK create_app:', a.name)"
if ($LASTEXITCODE -ne 0) { throw "Fallo create_app." }

& $Py -c "from app.services.word_report_service import build_case_docx; print('OK Word justificacion')"
if ($LASTEXITCODE -ne 0) { throw "Fallo importando Word." }

$routes = & $Py -c "from app import create_app; a=create_app(); print([(r.endpoint,str(r)) for r in a.url_map.iter_rules() if '/reports/' in str(r)])"
$routes | ForEach-Object { Write-Host $_ }

$templateText = Get-Content "app\templates\study_detail.html" -Raw -Encoding UTF8
if ($templateText -notmatch "reports\.word_case") { throw "No se encontro reports.word_case en study_detail.html." }
if ($templateText -notmatch "Justificaci") { throw "No se encontro el boton de justificacion." }

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS21 COMPLETADO CORRECTAMENTE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Siguiente paso:" -ForegroundColor Cyan
Write-Host "  .\91_validar_predemo_ps12_ps15_v2_3.ps1"
Write-Host "  .\dev.ps1"

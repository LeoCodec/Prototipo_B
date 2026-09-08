param()

$ErrorActionPreference = "Stop"
$Failures = 0

function Ok($m) { Write-Host "OK - $m" -ForegroundColor Green }
function Fail($m) { Write-Host "FALLO - $m" -ForegroundColor Red; $script:Failures++ }

Write-Host "========================================================" -ForegroundColor DarkGreen
Write-Host " IPPLIAP - PS35 VALIDACION EXCEL ANALITICO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor DarkGreen

Write-Host ""
Write-Host "[1] Rama main" -ForegroundColor Cyan
$Branch = (git branch --show-current).Trim()
Write-Host $Branch
if ($Branch -eq "main") { Ok "main" } else { Fail "No esta en main" }

Write-Host ""
Write-Host "[2] Compilacion" -ForegroundColor Cyan
python -m py_compile ".\app\services\institutional_form_service.py" ".\app\services\institutional_export_service.py"
if ($LASTEXITCODE -eq 0) { Ok "Python compila" } else { Fail "Compilacion" }

Write-Host ""
Write-Host "[3] Integrantes y per capita" -ForegroundColor Cyan

$TestPy = Join-Path $env:TEMP ("ippliap_ps35_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".py")

$Code = @'
from pathlib import Path
from tempfile import TemporaryDirectory
from openpyxl import load_workbook
from docx import Document

from app.services.institutional_form_service import calculate_reference, save_form
from app.services.institutional_export_service import build_case_excel, build_case_word, build_bulk_excel

data = {
    "household_size": "2",
    "turno": "Matutino",
    "fecha": "2026-09-08",
    "nombre_alumno": "Mateo",
    "apellido_paterno_alumno": "Rios",
    "apellido_materno_alumno": "Luna",
    "renta": "4500",
    "luz": "600",
    "agua": "350",
    "telefono_gasto": "450",
    "gas": "650",
    "alimentos": "4000",
    "automovil": "0",
    "pasajes": "1200",
    "colegiaturas": "0",
    "vestido": "600",
    "medico_medicinas": "500",
    "muebles_hogar": "0",
    "creditos_personales": "700",
    "otros_gastos": "300",
    "predial_anual": "0",
    "gastos_anuales": "0",
    "vacaciones_anual": "0",
    "observaciones": "Caso de validacion.",
    "contexto_sociofamiliar": "Ambos padres aportan al hogar.",
}
family = [
    {"nombre":"Maria Elena Luna Perez","parentesco":"Madre","edad":"34","ocupacion":"Auxiliar administrativa"},
    {"nombre":"Mateo Rios Luna","parentesco":"Hijo","edad":"8","ocupacion":"Estudiante"},
    {"nombre":"Carlos Rios Vega","parentesco":"Padre","edad":"36","ocupacion":"Tecnico"},
]
income_rows = [
    {"integrante":"Maria Elena Luna Perez","lugar_trabajo":"Servicios Administrativos","antiguedad":"4 anos","puesto":"Auxiliar","ingreso_mensual":"10500","aportacion_mensual":"10500"},
    {"integrante":"Carlos Rios Vega","lugar_trabajo":"Mantenimiento","antiguedad":"2 anos","puesto":"Tecnico","ingreso_mensual":"8000","aportacion_mensual":"5000"},
]

calc = calculate_reference(dict(data), family, income_rows)
print("CALCULO:", calc)
assert calc["household_size"] == 3, calc["household_size"]
assert calc["total_income"] == 15500.0, calc["total_income"]
assert calc["total_expenses"] == 13850.0, calc["total_expenses"]
assert calc["income_per_capita"] == 5166.67, calc["income_per_capita"]
assert calc["available_per_capita"] == 550.0, calc["available_per_capita"]
assert calc["reference_fee"] == 350.0, calc["reference_fee"]

class Study:
    id = 1
    folio = "ES-PRUEBA-001"
    student_name = "Mateo Rios Luna"
    status = "FORMULARIO"

with TemporaryDirectory() as tmp:
    payload = save_form(tmp, 1, {
        "data": data,
        "family_members": family,
        "income_rows": income_rows,
    })

    excel = build_case_excel(Study(), tmp)
    wb = load_workbook(excel)
    print("HOJAS EXCEL:", wb.sheetnames)
    assert wb.sheetnames == ["Resumen", "Analisis_economico", "Detalle_calculo"], wb.sheetnames
    assert len(wb["Resumen"]._charts) >= 3, len(wb["Resumen"]._charts)

    # El Excel individual ya no debe duplicar expediente personal completo.
    for old in ("Alumno","Solicitante","Familia","Vivienda","Salud_Contexto"):
        assert old not in wb.sheetnames, old

    word = build_case_word(Study(), tmp)
    doc = Document(word)
    text = "\n".join(p.text for p in doc.paragraphs)
    for required in (
        "ESTUDIO SOCIOECONÓMICO",
        "Datos generales del alumno",
        "Integrantes del hogar",
        "Situación económica",
        "Distribución del gasto familiar",
        "Lectura económica y valoración",
    ):
        assert required in text, required

    class Study2:
        id = 2
        folio = "ES-PRUEBA-002"
        student_name = "Caso Dos"
        status = "FORMULARIO"

    save_form(tmp, 2, {
        "data": dict(data, nombre_alumno="Caso", apellido_paterno_alumno="Dos"),
        "family_members": family,
        "income_rows": income_rows,
    })

    bulk = build_bulk_excel([Study(), Study2()], tmp)
    wb2 = load_workbook(bulk)
    print("HOJAS CONSOLIDADO:", wb2.sheetnames)
    assert "Estadísticas" in wb2.sheetnames
    assert "Casos" in wb2.sheetnames
    assert len(wb2["Estadísticas"]._charts) >= 2

print("VALIDACION_FUNCIONAL_OK")
'@

Set-Content -LiteralPath $TestPy -Value $Code -Encoding UTF8
python $TestPy

if ($LASTEXITCODE -eq 0) {
    Ok "Calculo, Word, Excel individual y consolidado"
} else {
    Fail "Validacion funcional"
}

Write-Host ""
Write-Host "[4] Rutas institucionales" -ForegroundColor Cyan
python -c "from app import create_app; a=create_app(); r=[str(x) for x in a.url_map.iter_rules() if '/estudios' in str(x)]; print(r); assert '/estudios/<int:study_id>/excel' in r; assert '/estudios/<int:study_id>/word' in r; assert '/estudios/exportar/excel' in r"
if ($LASTEXITCODE -eq 0) { Ok "Rutas" } else { Fail "Rutas" }

Write-Host ""
Write-Host "[5] Health" -ForegroundColor Cyan
python -c "from app import create_app; a=create_app(); r=a.test_client().get('/diagnostics/health'); print(r.status_code, r.get_json()); assert r.status_code==200"
if ($LASTEXITCODE -eq 0) { Ok "Health" } else { Fail "Health" }

Write-Host ""
Write-Host "[6] Git informativo" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "========================================================" -ForegroundColor DarkGreen
if ($Failures -eq 0) {
    Write-Host " VALIDACION PS35: 0 FALLOS" -ForegroundColor Green
    Write-Host " Listo para prueba manual antes del commit." -ForegroundColor Green
} else {
    Write-Host " VALIDACION PS35: $Failures FALLO(S)" -ForegroundColor Red
    Write-Host " NO HAGA COMMIT." -ForegroundColor Red
}
Write-Host "========================================================" -ForegroundColor DarkGreen

if ($Failures -gt 0) { exit 1 }

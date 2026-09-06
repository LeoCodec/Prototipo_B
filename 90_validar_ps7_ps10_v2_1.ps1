param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Continue"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    Write-Host "ERROR: no se encontro venv\Scripts\python.exe" -ForegroundColor Red
    exit 1
}

# Entorno estable para esta validacion.
$env:PYTHONPATH = "$ProjectPath;$env:PYTHONPATH"
$env:TESSERACT_CMD = "C:\Program Files\Tesseract-OCR\tesseract.exe"
$env:TESSDATA_PREFIX = Join-Path $ProjectPath "tools\tessdata"
$env:Path = "C:\Program Files\Tesseract-OCR;$env:Path"
$env:OCR_LANG = "spa"

$Failures = 0

function Check-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host $Name -ForegroundColor Cyan

    try {
        & $Action
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "El comando termino con codigo $LASTEXITCODE"
        }
        Write-Host "OK" -ForegroundColor Green
    }
    catch {
        $script:Failures++
        Write-Host "FALLO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - VALIDACION PS7 A PS10 v2.1" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Check-Step "[1] Tesseract + idioma espanol" {
    & "C:\Program Files\Tesseract-OCR\tesseract.exe" --version | Select-Object -First 1
    $langs = & "C:\Program Files\Tesseract-OCR\tesseract.exe" --list-langs 2>&1
    $langs | ForEach-Object { Write-Host $_ }

    if (-not ($langs | Where-Object { $_.Trim() -eq "spa" })) {
        throw "No aparece el idioma spa."
    }
}

Check-Step "[2] Importar aplicacion Flask" {
    & $Py -c "from app import create_app; a=create_app(); print('OK create_app:', a.name)"
}

Check-Step "[3] Verificar rutas PS7-PS10" {
    & $Py -c "from app import create_app; a=create_app(); required=['/fields/<int:study_id>','/fields/<int:study_id>/reprocess','/fields/<int:study_id>/run','/review-fields/<int:study_id>','/analysis/<int:study_id>','/reports/','/reports/<int:study_id>/excel','/reports/<int:study_id>/word','/reports/bulk-excel','/diagnostics/health']; routes={str(r) for r in a.url_map.iter_rules()}; missing=[r for r in required if r not in routes]; print('\n'.join(sorted(routes))); assert not missing, 'Faltan rutas: '+', '.join(missing)"
}

Check-Step "[4] OCR sintetico real con Tesseract spa" {
    $SmokePy = Join-Path $ProjectPath "_tmp_ippliap_ocr_smoke.py"

    @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

from app.services.ocr_service import extract_text

out = Path("instance/ocr_smoke_test.png")
out.parent.mkdir(parents=True, exist_ok=True)

img = Image.new("RGB", (1600, 650), "white")
draw = ImageDraw.Draw(img)

font_candidates = [
    r"C:\Windows\Fonts\arial.ttf",
    r"C:\Windows\Fonts\calibri.ttf",
]

font = None
for candidate in font_candidates:
    try:
        font = ImageFont.truetype(candidate, 64)
        break
    except Exception:
        pass

if font is None:
    font = ImageFont.load_default()

text = (
    "ESTUDIO SOCIOECONOMICO\n"
    "PASAJES: 850\n"
    "AGUA: 300\n"
    "OBSERVACIONES: PRUEBA DE CAPTURA"
)

draw.multiline_text(
    (80, 70),
    text,
    fill="black",
    font=font,
    spacing=28,
)

img.save(out)

result = extract_text(str(out))

print("Idioma:", result.get("language"))
print("Confianza:", result.get("confidence"))
print("Preprocesamiento:", result.get("preprocessing"))
print("Error:", result.get("error"))
print("Texto OCR:")
print(result.get("text", ""))

ocr = (result.get("text") or "").upper()

if result.get("error") and not ocr:
    raise SystemExit("OCR no produjo texto.")

if "PASAJES" not in ocr and "AGUA" not in ocr:
    raise SystemExit("OCR produjo texto, pero no reconocio los campos de prueba.")
'@ | Set-Content -Encoding UTF8 $SmokePy

    & $Py $SmokePy
    $code = $LASTEXITCODE
    Remove-Item $SmokePy -Force -ErrorAction SilentlyContinue

    if ($code -ne 0) {
        throw "La prueba OCR sintetica fallo con codigo $code"
    }
}

Check-Step "[5] Extraccion por campos" {
    $FieldPy = Join-Path $ProjectPath "_tmp_ippliap_fields_smoke.py"

    @'
from app.services.field_extraction import extract_fields

sample = """PASAJES: 850
AGUA: 300
OBSERVACIONES: Prueba de captura
"""

fields = extract_fields(sample)

print("Pasajes:", fields["pasajes"])
print("Agua:", fields["agua"])
print("Observaciones:", fields["observaciones"])

assert fields["pasajes"]["detected"] == "850"
assert fields["agua"]["detected"] == "300"
assert "Prueba de captura" in fields["observaciones"]["detected"]
'@ | Set-Content -Encoding UTF8 $FieldPy

    & $Py $FieldPy
    $code = $LASTEXITCODE
    Remove-Item $FieldPy -Force -ErrorAction SilentlyContinue

    if ($code -ne 0) {
        throw "La prueba de extraccion fallo con codigo $code"
    }
}

Check-Step "[6] Formulas socioeconomicas" {
    & $Py -m unittest tests.test_socioeconomic_metrics -v
}

Check-Step "[7] Importar generadores Excel y Word" {
    & $Py -c "from app.services.report_service import case_workbook, bulk_workbook; from app.services.word_report_service import build_case_docx; import openpyxl, docx; print('OK Excel/Word')"
}

Check-Step "[8] Dependencias del venv" {
    & $Py -m pip check
}

Check-Step "[9] Endpoint de salud" {
    & $Py -c "from app import create_app; a=create_app(); c=a.test_client(); r=c.get('/diagnostics/health'); print(r.status_code, r.get_json()); assert r.status_code==200; assert r.get_json().get('status')=='ok'"
}

Write-Host ""
Write-Host "[10] Estado Git" -ForegroundColor Cyan
git branch --show-current
git status --short

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green

if ($Failures -eq 0) {
    Write-Host " VALIDACION COMPLETA: 0 FALLOS" -ForegroundColor Green
    Write-Host " PS7-PS10 estan listos para prueba funcional en navegador." -ForegroundColor Green
    exit 0
}
else {
    Write-Host " VALIDACION TERMINADA CON $Failures FALLO(S)" -ForegroundColor Red
    Write-Host " No haga merge a main hasta corregirlos." -ForegroundColor Yellow
    exit 1
}

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

$env:PYTHONPATH = "$ProjectPath;$env:PYTHONPATH"
$env:TESSERACT_CMD = "C:\Program Files\Tesseract-OCR\tesseract.exe"
$env:TESSDATA_PREFIX = Join-Path $ProjectPath "tools\tessdata"
$env:Path = "C:\Program Files\Tesseract-OCR;$env:Path"
$env:OCR_LANG = "spa"

$Failures = 0

function Run-Check {
    param([string]$Title, [scriptblock]$Action)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    try {
        & $Action
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
            throw "Codigo de salida: $LASTEXITCODE"
        }
        Write-Host "OK" -ForegroundColor Green
    }
    catch {
        $script:Failures++
        Write-Host "FALLO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Run-TempPython {
    param([string]$Name, [string]$Code)
    $path = Join-Path $ProjectPath $Name
    $Code | Set-Content -Encoding UTF8 $path
    & $Py $path
    $code = $LASTEXITCODE
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    if ($code -ne 0) { throw "$Name fallo con codigo $code" }
}

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - VALIDACION PRE-DEMO PS12 A PS15 v2.3" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Run-Check "[1] Rama main y Python del venv" {
    $branch = (git branch --show-current).Trim()
    Write-Host "Rama: $branch"
    if ($branch -ne "main") { throw "La rama activa no es main." }
    & $Py -c "import sys; print(sys.executable)"
}

Run-Check "[2] Tesseract + idioma espanol" {
    $Tesseract = "C:\Program Files\Tesseract-OCR\tesseract.exe"
    if (-not (Test-Path $Tesseract)) { throw "No se encontro tesseract.exe." }
    & $Tesseract --version | Select-Object -First 1
    $langs = & $Tesseract --list-langs 2>&1
    $langs | ForEach-Object { Write-Host $_ }
    if (-not ($langs | Where-Object { $_.Trim() -eq "spa" })) { throw "No aparece el idioma spa." }
}

Run-Check "[3] Flask y rutas PS12-PS15" {
    $code = @'
from app import create_app

app = create_app()
routes = {str(rule) for rule in app.url_map.iter_rules()}
required = {
    "/",
    "/studies/<int:study_id>",
    "/fields/<int:study_id>",
    "/fields/<int:study_id>/reprocess",
    "/fields/<int:study_id>/run",
    "/review-fields/<int:study_id>",
    "/analysis/<int:study_id>",
    "/reports/",
    "/reports/<int:study_id>/excel",
    "/reports/<int:study_id>/word",
    "/reports/bulk-excel",
    "/cases/manage",
    "/cases/bulk-delete",
    "/auth/login",
    "/auth/logout",
    "/diagnostics/health",
}
missing = sorted(required - routes)
print("OK create_app:", app.name)
print("Rutas requeridas:", len(required) - len(missing), "/", len(required))
if missing:
    raise SystemExit("Faltan rutas: " + ", ".join(missing))
'@
    Run-TempPython "_tmp_predemo_routes.py" $code
}

Run-Check "[4] OCR sintetico real en espanol" {
    $code = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from app.services.ocr_service import extract_text

out = Path("instance/predemo_ocr.png")
out.parent.mkdir(parents=True, exist_ok=True)
img = Image.new("RGB", (1500, 600), "white")
draw = ImageDraw.Draw(img)
font = None
for candidate in [r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\calibri.ttf"]:
    try:
        font = ImageFont.truetype(candidate, 60)
        break
    except Exception:
        pass
if font is None:
    font = ImageFont.load_default()

draw.multiline_text(
    (70, 60),
    "ESTUDIO SOCIOECONOMICO\nPASAJES: 850\nAGUA: 300\nOBSERVACIONES: PRUEBA DE CAPTURA",
    fill="black",
    font=font,
    spacing=24,
)
img.save(out)

result = extract_text(str(out))
print("Idioma:", result.get("language"))
print("Confianza:", result.get("confidence"))
print("Error:", result.get("error"))
print(result.get("text", ""))
text = (result.get("text") or "").upper()
if result.get("error") and not text:
    raise SystemExit("OCR no produjo texto.")
if "PASAJES" not in text or "AGUA" not in text:
    raise SystemExit("OCR no reconocio los campos esperados.")
'@
    Run-TempPython "_tmp_predemo_ocr.py" $code
}

Run-Check "[5] Extraccion: MXN + Ninguno + colisiones" {
    $code = @'
from app.services.field_extraction import extract_fields

sample = """EDAD: 8
ENFERMEDADES CRONICAS EN LA FAMILIA: No hay
DOMICILIO: Calle Prueba 123
CROQUIS DEL DOMICILIO
PASAJES: Uinguno
COLEGIATURAS: No apica
AGUA: 300
VESTIDO: £ 600.00
OBSERVACIONES: Familia colaborativa y atenta.
"""
fields = extract_fields(sample)
checks = {
    "edad": fields["edad"]["detected"],
    "domicilio": fields["domicilio"]["detected"],
    "pasajes": fields["pasajes"]["detected"],
    "colegiaturas": fields["colegiaturas"]["detected"],
    "agua": fields["agua"]["detected"],
    "vestido": fields["vestido"]["detected"],
    "observaciones": fields["observaciones"]["detected"],
}
for key, value in checks.items():
    print(key, "=>", value)
assert checks["edad"] == "8"
assert checks["domicilio"] == "Calle Prueba 123"
assert checks["pasajes"] == "Ninguno"
assert checks["colegiaturas"] == "No aplica"
assert checks["agua"] == "$ 300.00 MXN"
assert checks["vestido"] == "$ 600.00 MXN"
assert "Familia colaborativa" in checks["observaciones"]
'@
    Run-TempPython "_tmp_predemo_fields.py" $code
}

Run-Check "[6] Formulas socioeconomicas" {
    & $Py -m unittest tests.test_socioeconomic_metrics -v
}

Run-Check "[7] Excel individual + Word + Excel consolidado" {
    $code = @'
from app.services.report_service import case_workbook
from app.services.word_report_service import build_case_docx
from app.services.bulk_report_service import build_bulk_workbook
import openpyxl
import docx

print("OK: Excel individual")
print("OK: Word individual")
print("OK: Excel consolidado")
'@
    Run-TempPython "_tmp_predemo_reports.py" $code
}

Run-Check "[8] Seguridad: headers y health check" {
    $code = @'
from app import create_app

app = create_app()
client = app.test_client()
response = client.get("/diagnostics/health")
print("Health:", response.status_code, response.get_json())
print("X-Content-Type-Options:", response.headers.get("X-Content-Type-Options"))
print("X-Frame-Options:", response.headers.get("X-Frame-Options"))
print("Referrer-Policy:", response.headers.get("Referrer-Policy"))
assert response.status_code == 200
assert response.get_json().get("status") == "ok"
assert response.headers.get("X-Content-Type-Options") == "nosniff"
assert response.headers.get("X-Frame-Options") == "DENY"
assert response.headers.get("Referrer-Policy") == "no-referrer"
'@
    Run-TempPython "_tmp_predemo_security.py" $code
}

Run-Check "[9] Auto-reload de desarrollo" {
    foreach ($file in @("dev.ps1", "dev_server.py")) {
        if (-not (Test-Path $file)) { throw "Falta $file" }
        Write-Host "$file presente"
    }
}

Run-Check "[10] Dependencias" {
    & $Py -m pip check
}

Write-Host ""
Write-Host "[11] Estado Git (informativo)" -ForegroundColor Cyan
git status --short

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
if ($Failures -eq 0) {
    Write-Host " VALIDACION PRE-DEMO COMPLETA: 0 FALLOS" -ForegroundColor Green
    Write-Host " PS12-PS15 listos para prueba funcional en navegador." -ForegroundColor Green
    exit 0
}

Write-Host " VALIDACION PRE-DEMO: $Failures FALLO(S)" -ForegroundColor Red
Write-Host " No haga commit todavia." -ForegroundColor Yellow
exit 1

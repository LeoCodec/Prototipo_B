param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Continue"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - VALIDACION PS7 A PS10 v2" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$env:TESSERACT_CMD = "C:\Program Files\Tesseract-OCR\tesseract.exe"
$env:TESSDATA_PREFIX = Join-Path $ProjectPath "tools\tessdata"
$env:Path = "C:\Program Files\Tesseract-OCR;$env:Path"
$env:OCR_LANG = "spa"

Write-Host "`n[1] Tesseract" -ForegroundColor Cyan
tesseract --version | Select-Object -First 1
tesseract --list-langs

Write-Host "`n[2] Imports y app" -ForegroundColor Cyan
& $Py -c "from app import create_app; a=create_app(); print('OK create_app:', a.name)"

Write-Host "`n[3] Rutas requeridas" -ForegroundColor Cyan
& $Py -c "from app import create_app; a=create_app(); r=[str(x) for x in a.url_map.iter_rules()]; print('\n'.join(x for x in sorted(r) if any(k in x for k in ['/fields','/review-fields','/analysis','/reports','/diagnostics'])))"

Write-Host "`n[4] Prueba OCR sintetica" -ForegroundColor Cyan
$testPy = @'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

from app.services.ocr_service import extract_text

path = Path("instance/ocr_smoke_test.png")
path.parent.mkdir(parents=True, exist_ok=True)

img = Image.new("RGB", (1400, 500), "white")
draw = ImageDraw.Draw(img)

try:
    font = ImageFont.truetype("arial.ttf", 54)
except Exception:
    font = ImageFont.load_default()

draw.text(
    (70, 70),
    "ESTUDIO SOCIOECONOMICO\nPASAJES: 850\nAGUA: 300",
    fill="black",
    font=font,
    spacing=24,
)

img.save(path)

result = extract_text(str(path))
print("Idioma:", result.get("language"))
print("Confianza:", result.get("confidence"))
print("Preprocesamiento:", result.get("preprocessing"))
print("Error:", result.get("error"))
print("Texto:")
print(result.get("text", "")[:1000])

if result.get("error") and not result.get("text"):
    raise SystemExit(2)
'@

$tmp = Join-Path $env:TEMP "ippliap_ocr_smoke.py"
$testPy | Set-Content -Encoding UTF8 $tmp
& $Py $tmp
Remove-Item $tmp -Force

Write-Host "`n[5] Prueba extractor de campos" -ForegroundColor Cyan
& $Py -c "from app.services.field_extraction import extract_fields; d=extract_fields('PASAJES: 850`nAGUA: 300`nOBSERVACIONES: Prueba de captura'); print(d['pasajes']); print(d['agua']); print(d['observaciones'])"

Write-Host "`n[6] Pruebas matematicas" -ForegroundColor Cyan
& $Py -m unittest tests.test_socioeconomic_metrics -v

Write-Host "`n[7] Dependencias" -ForegroundColor Cyan
& $Py -m pip check

Write-Host "`n[8] Git" -ForegroundColor Cyan
git branch --show-current
git status --short

Write-Host ""
Write-Host "VALIDACION TERMINADA" -ForegroundColor Green

param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    throw "No se encontro venv\Scripts\python.exe"
}

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS7.1 HOTFIX TESSDATA EN WINDOWS" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$service = Join-Path $ProjectPath "app\services\ocr_service.py"

if (-not (Test-Path $service)) {
    throw "No se encontro app\services\ocr_service.py"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "$service.bak_$stamp"
Copy-Item $service $backup -Force

Write-Host "Backup creado:" -ForegroundColor Cyan
Write-Host "  $backup"

$patch = @'
from pathlib import Path
import re

path = Path("app/services/ocr_service.py")
text = path.read_text(encoding="utf-8")

# El problema:
# En Windows, pasar --tessdata-dir con comillas dentro del string de config
# puede hacer que Tesseract reciba las comillas como parte de la ruta:
# "C:\...\tessdata"/spa.traineddata
#
# Ya configuramos TESSDATA_PREFIX, asi que no necesitamos --tessdata-dir.

patterns = [
    r'\n\s*if tessdata:\s*\n\s*config \+= f[\'"] --tessdata-dir .*?\n',
    r'\n\s*if tessdata:\s*\n\s*config \+= .*?--tessdata-dir.*?\n',
]

original = text
for pattern in patterns:
    text = re.sub(pattern, "\n", text, flags=re.MULTILINE)

# Parche puntual por si la linea existe sin el bloque completo.
text = re.sub(
    r'^\s*config \+= f[\'"] --tessdata-dir .*?$',
    '',
    text,
    flags=re.MULTILINE,
)

if text == original:
    print("No se encontro el bloque --tessdata-dir. Se verificara el archivo igualmente.")
else:
    path.write_text(text, encoding="utf-8")
    print("Se elimino --tessdata-dir del config de pytesseract.")
'@

$tmpPatch = Join-Path $env:TEMP "ippliap_patch_tessdata.py"
$patch | Set-Content -Encoding UTF8 $tmpPatch
& $Py $tmpPatch
Remove-Item $tmpPatch -Force

# Variables correctas para esta sesion.
$env:TESSERACT_CMD = "C:\Program Files\Tesseract-OCR\tesseract.exe"
$env:TESSDATA_PREFIX = Join-Path $ProjectPath "tools\tessdata"
$env:Path = "C:\Program Files\Tesseract-OCR;$env:Path"
$env:OCR_LANG = "spa"

Write-Host ""
Write-Host "[1] Verificando spa" -ForegroundColor Cyan
& "C:\Program Files\Tesseract-OCR\tesseract.exe" --list-langs

Write-Host ""
Write-Host "[2] Verificando configuracion desde Python" -ForegroundColor Cyan
& $Py -c "from app.services.ocr_service import _configure,_available_languages; print('Config:', _configure()); print('Idiomas:', _available_languages())"

Write-Host ""
Write-Host "[3] Prueba OCR sintetica" -ForegroundColor Cyan

$smoke = Join-Path $ProjectPath "_tmp_ocr_hotfix_test.py"

@'
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

from app.services.ocr_service import extract_text

out = Path("instance/ocr_hotfix_test.png")
out.parent.mkdir(parents=True, exist_ok=True)

img = Image.new("RGB", (1600, 650), "white")
draw = ImageDraw.Draw(img)

font = None
for candidate in [
    r"C:\Windows\Fonts\arial.ttf",
    r"C:\Windows\Fonts\calibri.ttf",
]:
    try:
        font = ImageFont.truetype(candidate, 64)
        break
    except Exception:
        pass

if font is None:
    font = ImageFont.load_default()

draw.multiline_text(
    (80, 70),
    "ESTUDIO SOCIOECONOMICO\nPASAJES: 850\nAGUA: 300\nOBSERVACIONES: PRUEBA DE CAPTURA",
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

if result.get("error") and not result.get("text"):
    raise SystemExit(2)

text = (result.get("text") or "").upper()
if "PASAJES" not in text and "AGUA" not in text:
    raise SystemExit(3)
'@ | Set-Content -Encoding UTF8 $smoke

& $Py $smoke
$code = $LASTEXITCODE
Remove-Item $smoke -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    Write-Host ""
    Write-Host "La prueba OCR sigue fallando. Codigo: $code" -ForegroundColor Red
    Write-Host "Se dejo backup en:" -ForegroundColor Yellow
    Write-Host "  $backup"
    exit $code
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " HOTFIX COMPLETADO: OCR SPA FUNCIONA" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Ahora vuelve a ejecutar:" -ForegroundColor Cyan
Write-Host "  .\90_validar_ps7_ps10_v2_1.ps1"

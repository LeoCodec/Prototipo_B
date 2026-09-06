param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS6.3 INSTALAR IDIOMA ESPANOL (spa)" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

$tesseract = "C:\Program Files\Tesseract-OCR\tesseract.exe"

if (-not (Test-Path $tesseract)) {
    throw "No se encontro Tesseract en $tesseract"
}

$localTessdata = Join-Path $ProjectPath "tools\tessdata"
New-Item -ItemType Directory -Force -Path $localTessdata | Out-Null

$spaFile = Join-Path $localTessdata "spa.traineddata"

if (-not (Test-Path $spaFile)) {
    Write-Host "Descargando modelo oficial spa.traineddata..." -ForegroundColor Cyan

    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/spa.traineddata" `
        -OutFile $spaFile
}

if (-not (Test-Path $spaFile)) {
    throw "No se pudo descargar spa.traineddata"
}

Write-Host "Modelo descargado:" -ForegroundColor Green
Write-Host "  $spaFile"

# Tesseract usa esta carpeta como origen de modelos.
$env:TESSDATA_PREFIX = $localTessdata
[Environment]::SetEnvironmentVariable(
    "TESSDATA_PREFIX",
    $localTessdata,
    "User"
)

$env:TESSERACT_CMD = $tesseract
[Environment]::SetEnvironmentVariable(
    "TESSERACT_CMD",
    $tesseract,
    "User"
)

Write-Host ""
Write-Host "Comprobando idiomas con el tessdata local..." -ForegroundColor Cyan
& $tesseract --list-langs

Write-Host ""
Write-Host "Comprobando desde Python/pytesseract..." -ForegroundColor Cyan
python -c "import os,pytesseract; print('TESSDATA_PREFIX=', os.environ.get('TESSDATA_PREFIX')); print('Idiomas pytesseract=', pytesseract.get_languages(config=''))"

Write-Host ""
Write-Host "Actualizando .env.example..." -ForegroundColor Cyan

$envExample = Join-Path $ProjectPath ".env.example"
if (-not (Test-Path $envExample)) {
    New-Item -ItemType File -Path $envExample | Out-Null
}

$lines = Get-Content $envExample -ErrorAction SilentlyContinue

if (-not ($lines | Where-Object { $_ -match '^\s*OCR_LANG=' })) {
    Add-Content -Encoding UTF8 $envExample "OCR_LANG=spa"
}

if (-not ($lines | Where-Object { $_ -match '^\s*TESSDATA_PREFIX=' })) {
    Add-Content -Encoding UTF8 $envExample "TESSDATA_PREFIX=$localTessdata"
}

if (-not ($lines | Where-Object { $_ -match '^\s*TESSERACT_CMD=' })) {
    Add-Content -Encoding UTF8 $envExample "TESSERACT_CMD=$tesseract"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS6.3 FINALIZADO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resultado esperado:" -ForegroundColor Cyan
Write-Host "  spa"
Write-Host ""
Write-Host "Despues ya puedes continuar con:" -ForegroundColor Green
Write-Host "  .\07_extraccion_campos.ps1"
Write-Host ""

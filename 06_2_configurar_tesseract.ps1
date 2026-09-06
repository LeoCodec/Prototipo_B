param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS6.2 - CONFIGURAR TESSERACT ===" -ForegroundColor Green

function Find-Tesseract {
    foreach ($candidate in @(
        "C:\Program Files\Tesseract-OCR\tesseract.exe",
        "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe"
    )) {
        if (Test-Path $candidate) { return $candidate }
    }

    $cmd = Get-Command tesseract.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$tesseract = Find-Tesseract

if (-not $tesseract) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "Tesseract no esta instalado y winget no esta disponible."
    }

    winget install --id UB-Mannheim.TesseractOCR -e `
        --accept-package-agreements --accept-source-agreements

    Start-Sleep -Seconds 2
    $tesseract = Find-Tesseract
}

if (-not $tesseract) { throw "No se pudo localizar tesseract.exe." }

$dir = Split-Path $tesseract -Parent
$env:TESSERACT_CMD = $tesseract
$env:Path = "$env:Path;$dir"
[Environment]::SetEnvironmentVariable("TESSERACT_CMD", $tesseract, "User")

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$dir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
}

Write-Host "Tesseract encontrado: $tesseract" -ForegroundColor Green
& $tesseract --version | Select-Object -First 3

$langs = & $tesseract --list-langs 2>&1
Write-Host "Idiomas:" -ForegroundColor Cyan
$langs | ForEach-Object { Write-Host "  $_" }

if ($langs -notcontains "spa") {
    Write-Host "ADVERTENCIA: no se detecto 'spa'. El OCR puede funcionar peor en español." -ForegroundColor Yellow
}

$envExample = ".env.example"
if (-not (Test-Path $envExample)) { New-Item -ItemType File $envExample | Out-Null }
$txt = Get-Content $envExample -Raw
if ($txt -notmatch "(?m)^OCR_LANG=") { Add-Content $envExample "`nOCR_LANG=spa" }
if ($txt -notmatch "(?m)^TESSERACT_CMD=") { Add-Content $envExample "`nTESSERACT_CMD=$tesseract" }

Write-Host "Reinicia Flask con: python run.py" -ForegroundColor Cyan

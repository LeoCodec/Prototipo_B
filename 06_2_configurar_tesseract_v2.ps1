param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS6.2 v2 CONFIGURAR TESSERACT OCR" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""

function Find-Tesseract {
    $candidates = @(
        "C:\Program Files\Tesseract-OCR\tesseract.exe",
        "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
        "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe",
        "$env:LOCALAPPDATA\Tesseract-OCR\tesseract.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Resolve-Path $candidate).Path
        }
    }

    $cmd = Get-Command tesseract.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # Búsqueda limitada en ubicaciones habituales.
    foreach ($root in @(
        "C:\Program Files",
        "C:\Program Files (x86)",
        "$env:LOCALAPPDATA\Programs"
    )) {
        if ($root -and (Test-Path $root)) {
            $found = Get-ChildItem $root -Filter "tesseract.exe" -File -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($found) {
                return $found.FullName
            }
        }
    }

    return $null
}

$tesseract = Find-Tesseract

if (-not $tesseract) {
    Write-Host "Tesseract no esta instalado. Intentando instalarlo desde el origen 'winget'..." -ForegroundColor Yellow

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget no esta disponible. Instala Tesseract manualmente y vuelve a ejecutar el script."
    }

    # IMPORTANTE:
    # Se fuerza --source winget para evitar que un error/certificado de msstore bloquee la instalación.
    & winget install `
        --id UB-Mannheim.TesseractOCR `
        -e `
        --source winget `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Winget devolvio codigo $LASTEXITCODE." -ForegroundColor Yellow
        Write-Host "Intentando localizar Tesseract por si la instalacion si se completo..." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 2
    $tesseract = Find-Tesseract
}

if (-not $tesseract) {
    Write-Host ""
    Write-Host "No se pudo localizar tesseract.exe." -ForegroundColor Red
    Write-Host ""
    Write-Host "Prueba manualmente este comando:" -ForegroundColor Cyan
    Write-Host 'winget install --id UB-Mannheim.TesseractOCR -e --source winget'
    Write-Host ""
    Write-Host "Despues ejecuta:" -ForegroundColor Cyan
    Write-Host 'Get-ChildItem "C:\Program Files","$env:LOCALAPPDATA\Programs" -Filter tesseract.exe -Recurse -ErrorAction SilentlyContinue | Select-Object FullName'
    exit 2
}

Write-Host ""
Write-Host "Tesseract localizado:" -ForegroundColor Green
Write-Host "  $tesseract"

$tesseractDir = Split-Path $tesseract -Parent

# Variables para la sesión actual
$env:TESSERACT_CMD = $tesseract
if (($env:Path -split ';') -notcontains $tesseractDir) {
    $env:Path = "$tesseractDir;$env:Path"
}

# Variables persistentes del usuario
[Environment]::SetEnvironmentVariable("TESSERACT_CMD", $tesseract, "User")

$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ([string]::IsNullOrWhiteSpace($currentUserPath)) {
    [Environment]::SetEnvironmentVariable("Path", $tesseractDir, "User")
}
elseif (($currentUserPath -split ';') -notcontains $tesseractDir) {
    [Environment]::SetEnvironmentVariable("Path", "$tesseractDir;$currentUserPath", "User")
}

Write-Host ""
Write-Host "Version:" -ForegroundColor Cyan
& $tesseract --version | Select-Object -First 3

Write-Host ""
Write-Host "Idiomas disponibles:" -ForegroundColor Cyan
$langsRaw = & $tesseract --list-langs 2>&1
$langsRaw | ForEach-Object { Write-Host "  $_" }

$hasSpa = $false
foreach ($line in $langsRaw) {
    if ($line.Trim() -eq "spa") {
        $hasSpa = $true
        break
    }
}

if ($hasSpa) {
    Write-Host ""
    Write-Host "OK: idioma español (spa) disponible." -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host "ATENCION: Tesseract funciona, pero no aparece el idioma 'spa'." -ForegroundColor Yellow
    Write-Host "No avances a PS7 todavía; primero instalaremos/verificaremos spa." -ForegroundColor Yellow
}

# Actualizar .env.example
$envExample = Join-Path $ProjectPath ".env.example"
if (-not (Test-Path $envExample)) {
    New-Item -ItemType File -Path $envExample | Out-Null
}

$lines = @()
if (Test-Path $envExample) {
    $lines = Get-Content $envExample
}

if (-not ($lines | Where-Object { $_ -match '^\s*OCR_LANG=' })) {
    Add-Content -Encoding UTF8 $envExample "OCR_LANG=spa"
}
if (-not ($lines | Where-Object { $_ -match '^\s*TESSERACT_CMD=' })) {
    Add-Content -Encoding UTF8 $envExample "TESSERACT_CMD=$tesseract"
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS6.2 FINALIZADO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pruebas inmediatas:" -ForegroundColor Cyan
Write-Host '  tesseract --version'
Write-Host '  tesseract --list-langs'
Write-Host '  python -c "import pytesseract; print(pytesseract.__version__)"'
Write-Host ""

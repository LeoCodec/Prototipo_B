param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Continue"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PRE-FLIGHT ANTES DE DEMO/DESPLIEGUE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Write-Host "`n[1] Git" -ForegroundColor Cyan
git status --short
git branch --show-current

Write-Host "`n[2] Archivos sensibles versionados" -ForegroundColor Cyan
$tracked = git ls-files
$bad = $tracked | Where-Object {
    $_ -match '(^|/)\.env$|^instance/|^uploads/.+\.(png|jpg|jpeg|webp|pdf)$|^exports/.+\.(xlsx|docx)$'
}
if ($bad) {
    Write-Host "ATENCION: hay archivos sensibles o de prueba versionados:" -ForegroundColor Red
    $bad
} else {
    Write-Host "OK: no se detectaron expedientes/exports sensibles versionados." -ForegroundColor Green
}

Write-Host "`n[3] Compilacion Python" -ForegroundColor Cyan
python -m compileall app -q
if ($LASTEXITCODE -eq 0) { Write-Host "OK compileall" -ForegroundColor Green }

Write-Host "`n[4] Importar aplicacion" -ForegroundColor Cyan
python -c "from app import create_app; a=create_app(); print('OK create_app:', a.name)"

Write-Host "`n[5] Tesseract" -ForegroundColor Cyan
$t = Get-Command tesseract.exe -ErrorAction SilentlyContinue
if ($t) {
    tesseract --version | Select-Object -First 1
    tesseract --list-langs
} else {
    Write-Host "Tesseract no aparece en PATH." -ForegroundColor Yellow
}

Write-Host "`n[6] Rutas Flask" -ForegroundColor Cyan
python -c "from app import create_app; a=create_app(); print('\n'.join(sorted(str(r) for r in a.url_map.iter_rules())))"

Write-Host "`n[7] Dependencias" -ForegroundColor Cyan
python -m pip check

Write-Host "`nPRE-FLIGHT TERMINADO" -ForegroundColor Green

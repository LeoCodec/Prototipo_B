param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS29 VALIDACION NAVBAR + UTF-8" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$Fails = 0

function Step($Name, [scriptblock]$Block) {
    Write-Host ""
    Write-Host $Name -ForegroundColor Cyan
    try {
        & $Block
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Codigo de salida $LASTEXITCODE"
        }
        Write-Host "OK" -ForegroundColor Green
    }
    catch {
        $script:Fails++
        Write-Host "FALLO: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Step "[1] Rama main" {
    $b = (git branch --show-current).Trim()
    Write-Host $b
    if ($b -ne "main") { throw "Debe estar en main." }
}

Step "[2] Base conserva estructura original" {
    $base = Get-Content ".\app\templates\base.html" -Raw -Encoding UTF8

    if ($base -notmatch 'class="sidebar"') {
        throw "No aparece la clase sidebar."
    }
    if ($base -notmatch 'ippliap-mark\.png|ippliap-mark\.svg|brand-mark|brand-logo') {
        throw "No aparece la estructura del logo."
    }
    if ($base -notmatch 'support|Apoyo humano') {
        throw "No aparece el bloque de apoyo humano."
    }
}

Step "[3] Navbar sin flujo viejo" {
    $m = Select-String `
        -Path ".\app\templates\base.html" `
        -Pattern "Captura|Procesamiento|Revisión OCR|Revision OCR|PILOTO EXPERIMENTAL" `
        -ErrorAction SilentlyContinue

    if ($m) {
        $m | Format-Table LineNumber,Line -AutoSize
        throw "Quedan opciones del flujo anterior."
    }
}

Step "[4] Navbar institucional" {
    $base = Get-Content ".\app\templates\base.html" -Raw -Encoding UTF8

    foreach ($text in @("Nuevo estudio","Casos","Reportes")) {
        if ($base -notmatch [regex]::Escape($text)) {
            throw "Falta '$text' en base.html."
        }
    }

    if ($base -notmatch "institutional\.index") {
        throw "No hay enlaces al flujo institucional."
    }
}

Step "[5] Macro de etiquetas" {
    $form = Get-Content ".\app\templates\institutional_form.html" -Raw -Encoding UTF8
    if ($form -notmatch '\{\{\s*label\|safe\s*\}\}') {
        throw "El macro todavia no usa label|safe."
    }
}

Step "[6] Render del formulario no duplica entidades" {
@'
from types import SimpleNamespace
from app import create_app
from flask import render_template

app = create_app()
study = SimpleNamespace(id=999, folio="ES-TEST", student_name="Prueba", status="FORMULARIO")
payload = {"data": {}, "family_members": [], "income_rows": [], "calculation": {}}

with app.test_request_context("/estudios/999"):
    html = render_template("institutional_form.html", study=study, payload=payload)

bad = ["&amp;eacute;", "&amp;uacute;", "&amp;oacute;", "&amp;aacute;", "&amp;ntilde;"]
found = [x for x in bad if x in html]
print("ENTIDADES_DUPLICADAS:", found)
if found:
    raise SystemExit("Hay entidades HTML doblemente escapadas.")
'@ | Set-Content -Encoding ASCII "_tmp_ps29_render.py"

    python "_tmp_ps29_render.py"
    Remove-Item "_tmp_ps29_render.py" -Force -ErrorAction SilentlyContinue
}

Step "[7] Rutas institucionales" {
@'
from app import create_app
app = create_app()
routes = {str(r) for r in app.url_map.iter_rules()}
required = {
    "/estudios/",
    "/estudios/nuevo",
    "/estudios/<int:study_id>",
    "/estudios/<int:study_id>/guardar",
    "/estudios/<int:study_id>/preview",
    "/estudios/<int:study_id>/excel",
    "/estudios/<int:study_id>/word",
    "/estudios/exportar/excel",
}
missing = required - routes
print("RUTAS:", sorted(r for r in routes if r.startswith("/estudios")))
if missing:
    raise SystemExit("Faltan rutas: " + ", ".join(sorted(missing)))
'@ | Set-Content -Encoding ASCII "_tmp_ps29_routes.py"

    python "_tmp_ps29_routes.py"
    Remove-Item "_tmp_ps29_routes.py" -Force -ErrorAction SilentlyContinue
}

Step "[8] Health" {
@'
from app import create_app
app = create_app()
r = app.test_client().get("/diagnostics/health")
print(r.status_code, r.get_json())
if r.status_code != 200:
    raise SystemExit("Health fallo.")
'@ | Set-Content -Encoding ASCII "_tmp_ps29_health.py"

    python "_tmp_ps29_health.py"
    Remove-Item "_tmp_ps29_health.py" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "========================================================"
if ($Fails -eq 0) {
    Write-Host " VALIDACION NAVBAR + UTF-8: 0 FALLOS" -ForegroundColor Green
    Write-Host " Recargue con Ctrl+F5." -ForegroundColor Green
}
else {
    Write-Host " VALIDACION NAVBAR + UTF-8: $Fails FALLO(S)" -ForegroundColor Red
    Write-Host " NO HAGA COMMIT." -ForegroundColor Red
}
Write-Host "========================================================"

exit $Fails


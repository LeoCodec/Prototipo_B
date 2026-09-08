param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Continue"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS33 VALIDAR ELIMINAR EXACTO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$Fails = 0

function Check($Title, [scriptblock]$Block) {
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
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

Check "[1] Rama main" {
    $b = (git branch --show-current).Trim()
    Write-Host $b
    if ($b -ne "main") { throw "Debe estar en main." }
}

Check "[2] Ruta eliminar acepta POST" {
    $Py = @'
from app import create_app
app = create_app()
matches = [(str(r), sorted(r.methods)) for r in app.url_map.iter_rules() if "eliminar" in str(r)]
print(matches)
if not matches:
    raise SystemExit("No existe ruta eliminar.")
if not any("POST" in methods for _, methods in matches):
    raise SystemExit("La ruta eliminar no acepta POST.")
'@
    $Py | Set-Content -Encoding UTF8 "_tmp_ps33_route.py"
    python "_tmp_ps33_route.py"
    Remove-Item "_tmp_ps33_route.py" -Force -ErrorAction SilentlyContinue
}

Check "[3] HTML correcto" {
    $t = Get-Content ".\app\templates\institutional_cases.html" -Raw -Encoding UTF8

    if ($t -match '<form[^>]+institutional\.delete') {
        throw "Sigue existiendo un form interno para eliminar."
    }
    if ($t -notmatch 'formaction=.*institutional\.delete') {
        throw "No aparece formaction para eliminar."
    }
    if ($t -notmatch 'formmethod="post"') {
        throw "No aparece formmethod=post."
    }
    if ($t -notmatch 'Eliminar definitivamente este caso') {
        throw "No aparece la confirmacion."
    }
}

Check "[4] Render /estudios/" {
    $Py = @'
from app import create_app
app = create_app()
client = app.test_client()
r = client.get("/estudios/")
print("STATUS:", r.status_code)
if r.status_code != 200:
    raise SystemExit("GET /estudios/ fallo.")
html = r.get_data(as_text=True)
if "Eliminar" in html:
    print("BOTON_ELIMINAR: SI")
    if 'formmethod="post"' not in html:
        raise SystemExit("El boton renderizado no conserva formmethod=post.")
else:
    print("BOTON_ELIMINAR: NO HAY CASOS PARA MOSTRAR")
'@
    $Py | Set-Content -Encoding UTF8 "_tmp_ps33_render.py"
    python "_tmp_ps33_render.py"
    Remove-Item "_tmp_ps33_render.py" -Force -ErrorAction SilentlyContinue
}

Check "[5] Health" {
    $Py = @'
from app import create_app
app = create_app()
r = app.test_client().get("/diagnostics/health")
print(r.status_code, r.get_json())
if r.status_code != 200:
    raise SystemExit("Health fallo.")
'@
    $Py | Set-Content -Encoding UTF8 "_tmp_ps33_health.py"
    python "_tmp_ps33_health.py"
    Remove-Item "_tmp_ps33_health.py" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "========================================================"
if ($Fails -eq 0) {
    Write-Host " VALIDACION ELIMINAR: 0 FALLOS" -ForegroundColor Green
    Write-Host " Pruebe ahora el boton Eliminar en /estudios/." -ForegroundColor Green
}
else {
    Write-Host " VALIDACION ELIMINAR: $Fails FALLO(S)" -ForegroundColor Red
    Write-Host " NO HAGA COMMIT." -ForegroundColor Red
}
Write-Host "========================================================"

exit $Fails

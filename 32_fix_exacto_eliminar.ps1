param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS32 FIX EXACTO BOTON ELIMINAR" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$File = ".\app\templates\institutional_cases.html"
if (-not (Test-Path $File)) { throw "No se encontro $File" }

$Branch = (git branch --show-current).Trim()
Write-Host "Rama: $Branch" -ForegroundColor Cyan
if ($Branch -ne "main") { throw "Debe estar en main." }

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = "$File.pre_ps32_$Stamp"
Copy-Item $File $Backup -Force
Write-Host "Backup temporal: $Backup" -ForegroundColor Yellow

$Py = @'
from pathlib import Path

path = Path("app/templates/institutional_cases.html")
text = path.read_text(encoding="utf-8-sig")

old = """<form method="POST" action="{{ url_for('institutional.delete', study_id=study.id) }}" onsubmit="return confirm('?Eliminar definitivamente este caso?');"><button class="btn btn-danger" type="submit">Eliminar</button></form>"""

old2 = """<form method="POST" action="{{ url_for('institutional.delete', study_id=study.id) }}" onsubmit="return confirm('¿Eliminar definitivamente este caso?');"><button class="btn btn-danger" type="submit">Eliminar</button></form>"""

new = """<button class="btn btn-danger"
        type="submit"
        formaction="{{ url_for('institutional.delete', study_id=study.id) }}"
        formmethod="post"
        onclick="return confirm('¿Eliminar definitivamente este caso?');">Eliminar</button>"""

if old in text:
    text = text.replace(old, new)
    found = "VARIANTE_ASCII"
elif old2 in text:
    text = text.replace(old2, new)
    found = "VARIANTE_UTF8"
else:
    raise SystemExit("No se encontro el bloque exacto de Eliminar. No se modifico el archivo.")

path.write_text(text, encoding="utf-8", newline="\n")
print("REEMPLAZO_OK:", found)
'@

$Tmp = Join-Path $env:TEMP "ippliap_ps32_patch.py"
$Py | Set-Content -Encoding UTF8 $Tmp
python $Tmp
if ($LASTEXITCODE -ne 0) { throw "No fue posible aplicar PS32." }
Remove-Item $Tmp -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[1] Confirmando HTML" -ForegroundColor Cyan
$Txt = Get-Content $File -Raw -Encoding UTF8

if ($Txt -match '<form[^>]+institutional\.delete') {
    throw "Todavia existe un form interno de eliminar."
}
if ($Txt -notmatch 'formaction=.*institutional\.delete') {
    throw "No aparece el nuevo boton con formaction."
}
Write-Host "OK" -ForegroundColor Green

Write-Host ""
Write-Host "[2] Compilacion y Flask" -ForegroundColor Cyan
python -m compileall app -q
if ($LASTEXITCODE -ne 0) { throw "Fallo compileall." }

python -c "from app import create_app; a=create_app(); print('create_app OK:', a.name)"
if ($LASTEXITCODE -ne 0) { throw "Fallo create_app." }
Write-Host "OK" -ForegroundColor Green

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS32 COMPLETADO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Siguiente: .\33_validar_eliminar_exacto.ps1" -ForegroundColor Cyan

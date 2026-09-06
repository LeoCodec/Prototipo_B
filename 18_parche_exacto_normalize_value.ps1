param(
    [string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B"
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
$File = Join-Path $ProjectPath "app\services\field_extraction.py"

if (-not (Test-Path $Py)) { throw "No se encontro el Python del venv." }
if (-not (Test-Path $File)) { throw "No se encontro field_extraction.py." }
if ((git branch --show-current).Trim() -ne "main") { throw "Ejecutar solamente en main." }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS18 PARCHE EXACTO normalize_value" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "$File.bak_ps18_$stamp"
Copy-Item $File $backup -Force
Write-Host "Backup: $backup" -ForegroundColor Cyan

$old = @'
def normalize_value(value, kind):
    value=(value or '').strip()
    if not value: return ''
    if kind in {'money','money_or_none'}:
        n=money(value)
        if n is not None: return f'$ {n:,.2f} MXN'
        c=controlled(value)
        return c or value
    if kind=='integer':
        m=re.search(r'\b\d{1,3}\b', value); return m.group(0) if m else value
    c=controlled(value)
    return c if c and len(value.split()) <= 3 else value
'@

$new = @'
def normalize_value(value, kind):
    value=(value or '').strip()
    if not value: return ''

    if kind=='money_or_none':
        c=controlled(value)
        if c in {"Ninguno","Ninguna","No aplica","No"}:
            return c
        n=money(value)
        if n is not None:
            return f'$ {n:,.2f} MXN'
        return c or value

    if kind=='money':
        n=money(value)
        if n is not None:
            return f'$ {n:,.2f} MXN'
        c=controlled(value)
        return c or value

    if kind=='integer':
        m=re.search(r'\b\d{1,3}\b', value)
        return m.group(0) if m else value

    c=controlled(value)
    return c if c and len(value.split()) <= 3 else value
'@

$text = Get-Content $File -Raw -Encoding UTF8

if (-not $text.Contains($old)) {
    Write-Host "No se encontro el bloque EXACTO esperado." -ForegroundColor Red
    Write-Host "No se modifico el archivo." -ForegroundColor Yellow
    exit 2
}

$text = $text.Replace($old, $new)
Set-Content -Path $File -Value $text -Encoding UTF8
Write-Host "Bloque normalize_value reemplazado." -ForegroundColor Green

Write-Host ""
Write-Host "[1] Compilacion" -ForegroundColor Cyan
& $Py -m compileall app -q
if ($LASTEXITCODE -ne 0) {
    throw "Fallo compileall."
}
Write-Host "OK compileall" -ForegroundColor Green

Write-Host ""
Write-Host "[2] Prueba puntual" -ForegroundColor Cyan

$test = Join-Path $ProjectPath "_tmp_ps18_test.py"

@'
from app.services.field_extraction import extract_fields

sample = """EDAD: 8
ENFERMEDADES CRONICAS EN LA FAMILIA: No hay
DOMICILIO: Calle Prueba 123
CROQUIS DEL DOMICILIO
PASAJES: Uinguno
COLEGIATURAS: No apica
OTROS GASTOS: Minguno
AGUA: 300
VESTIDO: 600.00
MEDICO Y MEDICINAS: 300.00
OBSERVACIONES: Familia colaborativa y atenta.
"""

f = extract_fields(sample)

expected = {
    "edad": "8",
    "domicilio": "Calle Prueba 123",
    "pasajes": "Ninguno",
    "colegiaturas": "No aplica",
    "otros_gastos": "Ninguno",
    "agua": "$ 300.00 MXN",
    "vestido": "$ 600.00 MXN",
    "medico_medicinas": "$ 300.00 MXN",
}

for key, wanted in expected.items():
    got = f[key]["detected"]
    print(f"{key}: {got}")
    assert got == wanted, f"{key}: esperado={wanted!r}, obtenido={got!r}"

print("OK PS18")
'@ | Set-Content -Path $test -Encoding UTF8

& $Py $test
$code = $LASTEXITCODE
Remove-Item $test -Force -ErrorAction SilentlyContinue

if ($code -ne 0) {
    Write-Host "La prueba PS18 fallo. Backup disponible:" -ForegroundColor Red
    Write-Host $backup -ForegroundColor Yellow
    exit $code
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS18 COMPLETADO CORRECTAMENTE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Ahora ejecute:" -ForegroundColor Cyan
Write-Host "  .\91_validar_predemo_ps12_ps15_v2_3.ps1"

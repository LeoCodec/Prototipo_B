param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS28 HOTFIX NAVBAR + ETIQUETAS UTF-8" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

if (-not (Test-Path ".\app\templates\base.html")) {
    throw "Ejecute este script desde la raiz de Prototipo_B."
}

$Branch = (git branch --show-current).Trim()
Write-Host "Rama: $Branch" -ForegroundColor Cyan
if ($Branch -ne "main") {
    throw "Debe estar en main."
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = ".\app\templates\base.html.pre_ps28_$Stamp"
Copy-Item ".\app\templates\base.html" $Backup -Force
Write-Host "Backup temporal: $Backup" -ForegroundColor Yellow

$Patch = @'
from pathlib import Path
import html
import re
import subprocess

root = Path.cwd()
base_path = root / "app/templates/base.html"
form_path = root / "app/templates/institutional_form.html"

# Recupera la estructura visual que ya funcionaba antes de PS25.
try:
    base = subprocess.check_output(
        ["git", "show", "HEAD:app/templates/base.html"],
        text=True,
        encoding="utf-8",
        errors="strict",
    )
except Exception as exc:
    raise SystemExit(f"No fue posible recuperar base.html desde HEAD: {exc}")

def plain_text(fragment: str) -> str:
    text = re.sub(r"<[^>]+>", " ", fragment)
    text = html.unescape(text)
    return " ".join(text.split()).strip().lower()

def set_href(attrs: str, href: str) -> str:
    if re.search(r'\bhref\s*=', attrs, flags=re.I):
        return re.sub(
            r'\bhref\s*=\s*(["\']).*?\1',
            f'href="{href}"',
            attrs,
            count=1,
            flags=re.I | re.S,
        )
    return attrs + f' href="{href}"'

def anchor_repl(match):
    attrs = match.group("attrs")
    body = match.group("body")
    label = plain_text(body)

    # Quitamos del flujo visible lo que ya no se usa.
    if "captura" == label or "procesamiento" == label or "revisi\u00f3n ocr" == label or "revision ocr" == label:
        return ""

    if "nuevo caso" in label:
        attrs = set_href(attrs, "{{ url_for('institutional.index') }}#nuevo")
        body = re.sub(r"Nuevo\s+caso", "Nuevo estudio", body, flags=re.I)
    elif label == "casos":
        attrs = set_href(attrs, "{{ url_for('institutional.index') }}")
    elif label == "reportes":
        attrs = set_href(attrs, "{{ url_for('institutional.index') }}")

    return "<a" + attrs + ">" + body + "</a>"

base = re.sub(
    r"<a(?P<attrs>\b[^>]*)>(?P<body>.*?)</a>",
    anchor_repl,
    base,
    flags=re.I | re.S,
)

# Rebranding visible, conservando las clases y estructura CSS originales.
replacements = [
    ("DIGITALIZACI\u00d3N ASISTIDA", "GESTI\u00d3N INSTITUCIONAL"),
    ("Digitalizaci\u00f3n asistida", "Gesti\u00f3n institucional"),
    ("PILOTO EXPERIMENTAL", "GESTI\u00d3N INSTITUCIONAL"),
    ("Piloto activo", "Sistema activo"),
    ("Prototipo B \u00b7 Captura \u00b7 OpenCV \u00b7 OCR \u00b7 Revisi\u00f3n \u00b7 Reportes",
     "Estudios socioecon\u00f3micos \u00b7 Formularios \u00b7 C\u00e1lculos \u00b7 Word \u00b7 Excel"),
    ("Prototipo B", "Estudios socioecon\u00f3micos"),
]
for old, new in replacements:
    base = base.replace(old, new)

base_path.write_text(base, encoding="utf-8", newline="\n")

# Las etiquetas del macro traen entidades HTML como Tel&eacute;fono.
# Jinja las estaba escapando de nuevo (&amp;eacute;). Como las etiquetas
# son constantes del template, se pueden renderizar como HTML seguro.
form = form_path.read_text(encoding="utf-8-sig")
old = "{{ label }}"
new = "{{ label|safe }}"
if new not in form:
    if old not in form:
        raise SystemExit("No se encontro el macro {{ label }} en institutional_form.html")
    form = form.replace(old, new, 1)

form_path.write_text(form, encoding="utf-8", newline="\n")

print("BASE_RESTAURADA_DESDE_HEAD=OK")
print("MACRO_LABEL_SAFE=OK")
'@

$Tmp = Join-Path $env:TEMP "ippliap_ps28_patch.py"
$Patch | Set-Content -Encoding ASCII $Tmp

python $Tmp
if ($LASTEXITCODE -ne 0) {
    throw "Fallo el parche PS28."
}

Remove-Item $Tmp -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[1] Compilacion" -ForegroundColor Cyan
python -m compileall app -q
if ($LASTEXITCODE -ne 0) {
    throw "Fallo compileall."
}
Write-Host "OK" -ForegroundColor Green

Write-Host ""
Write-Host "[2] Flask" -ForegroundColor Cyan
python -c "from app import create_app; a=create_app(); print('create_app OK:', a.name)"
if ($LASTEXITCODE -ne 0) {
    throw "Fallo create_app."
}
Write-Host "OK" -ForegroundColor Green

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS28 COMPLETADO" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Ahora ejecute:" -ForegroundColor Cyan
Write-Host "  .\29_validar_navbar_utf8.ps1"

param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "=== IPPLIAP PS11 - PREPARAR PYTHONANYWHERE ===" -ForegroundColor Green

New-Item -ItemType Directory -Force "deployment" | Out-Null

@'
from app import create_app
application = create_app()
'@ | Set-Content -Encoding UTF8 "wsgi.py"

@'
import os
import sys

PROJECT = "/home/YOURUSERNAME/Prototipo_B"
if PROJECT not in sys.path:
    sys.path.insert(0, PROJECT)

os.environ.setdefault("OCR_LANG", "spa")

# Confirmar primero con:
# which tesseract
# os.environ.setdefault("TESSERACT_CMD", "/usr/bin/tesseract")

from app import create_app
application = create_app()
'@ | Set-Content -Encoding UTF8 "deployment\pythonanywhere_wsgi.py.template"

@'
# Despliegue del Prototipo B en PythonAnywhere

## Clonar

```bash
git clone https://github.com/LeoCodec/Prototipo_B.git
cd Prototipo_B
```

## Virtualenv

Use la misma versión de Python que seleccione para la Web App.

```bash
mkvirtualenv --python=/usr/bin/python3.13 prototipo-b
workon prototipo-b
pip install -r requirements.txt
```

## OCR

```bash
which tesseract
tesseract --version
tesseract --list-langs
```

No copie la ruta de Windows. Use la ruta Linux real que devuelva `which tesseract`.

## Web App

1. Web
2. Add a new web app
3. Manual configuration
4. Misma versión de Python que el virtualenv
5. Configurar el virtualenv `prototipo-b`
6. Editar el archivo WSGI con `pythonanywhere_wsgi.py.template`

## Static files

Si fuera necesario:

```text
URL: /static/
Directory: /home/YOURUSERNAME/Prototipo_B/app/static
```

## Importante

No llame `app.run()` desde el archivo WSGI.

`run.py` puede contenerlo únicamente dentro de:

```python
if __name__ == "__main__":
    app.run(...)
```

## Prueba de aceptación

1. Inicio
2. Crear caso ficticio
3. Capturar una página
4. OpenCV
5. OCR
6. Extracción
7. Revisión humana
8. Cálculos
9. Excel individual
10. Excel múltiple
11. Word
12. Eliminar un caso ficticio

No utilizar expedientes reales durante la demo pública.
'@ | Set-Content -Encoding UTF8 "deployment\DEPLOY_PYTHONANYWHERE.md"

$ignore = @(
    ".env",
    "venv/",
    "__pycache__/",
    "*.pyc",
    "instance/",
    "uploads/*",
    "!uploads/.gitkeep",
    "exports/*",
    "!exports/.gitkeep",
    "backup_ps*/",
    "*.log"
)

if (-not (Test-Path ".gitignore")) { New-Item -ItemType File ".gitignore" | Out-Null }
$current = Get-Content ".gitignore" -Raw

foreach ($entry in $ignore) {
    if ($current -notmatch "(?m)^$([regex]::Escape($entry))$") {
        Add-Content ".gitignore" "`n$entry"
    }
}

Write-Host "PS11 preparado." -ForegroundColor Green
Write-Host "Lea deployment\DEPLOY_PYTHONANYWHERE.md" -ForegroundColor Cyan

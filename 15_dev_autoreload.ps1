param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath
$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }

Write-Host "=== IPPLIAP PS15 - AUTO-RELOAD DE DESARROLLO ===" -ForegroundColor Green

@'
from __future__ import annotations
import os
from app import create_app
app=create_app(); app.config["TEMPLATES_AUTO_RELOAD"]=True; app.jinja_env.auto_reload=True
if __name__=="__main__":
    app.run(host=os.getenv("DEV_HOST","127.0.0.1"),port=int(os.getenv("DEV_PORT","5000")),debug=False,use_reloader=True,use_debugger=False)
'@ | Set-Content -Encoding UTF8 "dev_server.py"

@'
param([switch]$Lan)
$ProjectPath=Split-Path -Parent $MyInvocation.MyCommand.Path
$Py=Join-Path $ProjectPath "venv\Scripts\python.exe"
$env:DEV_HOST = $(if($Lan){"0.0.0.0"}else{"127.0.0.1"})
$env:DEV_PORT="5000"
if($Lan){ Write-Host "Acceso LAN activo. Use solo una Wi-Fi de confianza." -ForegroundColor Yellow }
& $Py (Join-Path $ProjectPath "dev_server.py")
'@ | Set-Content -Encoding UTF8 "dev.ps1"

Write-Host "PS15 listo. Use .\dev.ps1 o .\dev.ps1 -Lan" -ForegroundColor Green

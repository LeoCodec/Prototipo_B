param([switch]$Lan)
$ProjectPath=Split-Path -Parent $MyInvocation.MyCommand.Path
$Py=Join-Path $ProjectPath "venv\Scripts\python.exe"
$env:DEV_HOST = $(if($Lan){"0.0.0.0"}else{"127.0.0.1"})
$env:DEV_PORT="5000"
if($Lan){ Write-Host "Acceso LAN activo. Use solo una Wi-Fi de confianza." -ForegroundColor Yellow }
& $Py (Join-Path $ProjectPath "dev_server.py")

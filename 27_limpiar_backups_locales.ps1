param([string]$ProjectPath=(Get-Location).Path,[switch]$Confirmar)
$ErrorActionPreference="Stop";Set-Location $ProjectPath
Write-Host "========================================================" -ForegroundColor Yellow
Write-Host " IPPLIAP - PS27 LIMPIEZA DE BACKUPS LOCALES" -ForegroundColor Yellow
Write-Host "========================================================" -ForegroundColor Yellow
$Dirs=Get-ChildItem $ProjectPath -Directory -ErrorAction SilentlyContinue|Where-Object{$_.Name-like"backup_ps*"-or$_.Name-like"backup_pre_formulario_*"-or$_.Name-like"backup_ps24*"}
$Bak=Get-ChildItem ".\app" -Recurse -File -ErrorAction SilentlyContinue|Where-Object{$_.Name-like"*.bak_*"-or$_.Name-like"*.bak_ps*"}
Write-Host "`nDirectorios:" -ForegroundColor Cyan;$Dirs|ForEach-Object{Write-Host "  $($_.FullName)"}
Write-Host "`nArchivos .bak:" -ForegroundColor Cyan;$Bak|ForEach-Object{Write-Host "  $($_.FullName)"}
if(-not$Confirmar){Write-Host "`nMODO VISTA PREVIA: no se elimino nada." -ForegroundColor Yellow;Write-Host "Para eliminar: .\27_limpiar_backups_locales.ps1 -Confirmar";exit 0}
$Dirs|ForEach-Object{Remove-Item $_.FullName -Recurse -Force};$Bak|ForEach-Object{Remove-Item $_.FullName -Force}
Write-Host "`nLIMPIEZA COMPLETADA." -ForegroundColor Green
Write-Host "No se tocaron .env, instance, base de datos, exports, uploads ni scripts historicos." -ForegroundColor Green

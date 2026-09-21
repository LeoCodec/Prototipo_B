param()
$ErrorActionPreference = "Stop"
$Failures = 0

function OK($m) {
    Write-Host "OK - $m" -ForegroundColor Green
}
function FAIL($m) {
    Write-Host "FALLO - $m" -ForegroundColor Red
    $script:Failures++
}

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS37B VALIDACION FINAL" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

Set-Location "C:\Users\Leo\Documents\Prototipo_B"
$env:PYTHONPATH = (Get-Location).Path

if ((git branch --show-current).Trim() -eq "main") { OK "Rama main" } else { FAIL "Rama" }

python -m py_compile `
    ".\app\services\institutional_form_service.py" `
    ".\app\services\institutional_export_service.py"

if ($LASTEXITCODE -eq 0) { OK "Compilacion" } else { FAIL "Compilacion" }

$Html = Get-Content ".\app\templates\institutional_form.html" -Raw -Encoding UTF8
foreach ($Text in @(
    "Fecha de entrevista",
    "Responsable",
    "Responsables seleccionados",
    "Gastos adicionales o apoyos especiales",
    "Enlace de Google Maps confirmado",
    "Aspectos detectados para revisi"
)) {
    if ($Html.Contains($Text)) { OK $Text } else { FAIL "Falta: $Text" }
}

$TestFile = Join-Path $env:TEMP "ippliap_ps37b_test.py"
$TestBase64 = "ZnJvbSB0ZW1wZmlsZSBpbXBvcnQgVGVtcG9yYXJ5RGlyZWN0b3J5CmZyb20gb3BlbnB5eGwgaW1wb3J0IGxvYWRfd29ya2Jvb2sKZnJvbSBkb2N4IGltcG9ydCBEb2N1bWVudApmcm9tIGFwcC5zZXJ2aWNlcy5pbnN0aXR1dGlvbmFsX2Zvcm1fc2VydmljZSBpbXBvcnQgY2FsY3VsYXRlX3JlZmVyZW5jZSwgc2F2ZV9mb3JtLCBtYXBzX3NlYXJjaF91cmwKZnJvbSBhcHAuc2VydmljZXMuaW5zdGl0dXRpb25hbF9leHBvcnRfc2VydmljZSBpbXBvcnQgYnVpbGRfY2FzZV9leGNlbCwgYnVpbGRfY2FzZV93b3JkCgpkYXRhID0gewogICAgImZlY2hhIjogIjIwMjYtMDktMTQiLAogICAgIm5vbWJyZV9hbHVtbm8iOiAiSmFjb24gQWJkaWVsIiwKICAgICJhcGVsbGlkb19wYXRlcm5vX2FsdW1ubyI6ICJHdXRpZXJyZXoiLAogICAgImFwZWxsaWRvX21hdGVybm9fYWx1bW5vIjogIk1vbnRhw7FvIiwKICAgICJyZW50YSI6ICI1MDAiLAogICAgImx1eiI6ICIyNTAiLAogICAgImFndWEiOiAiMjUwIiwKICAgICJ0ZWxlZm9ub19nYXN0byI6ICIyMDAiLAogICAgImdhcyI6ICIxOTkuOTkiLAogICAgImFsaW1lbnRvcyI6ICIxNTAwIiwKICAgICJhdXRvbW92aWwiOiAiMCIsCiAgICAicGFzYWplcyI6ICIxNjAwIiwKICAgICJjb2xlZ2lhdHVyYXMiOiAiMCIsCiAgICAibWVkaWNvX21lZGljaW5hcyI6ICIzMDAiLAogICAgImJlY2FfYWN0dWFsX3BjdCI6ICIyNSIsCiAgICAic2VydmljaW9fbWVkaWNvIjogIlRlbGV0w7NuIElOUCIsCiAgICAib2JzZXJ2YWNpb25lcyI6ICJFbCBhbHVtbm8gcmVxdWllcmUgc2VndWltaWVudG8gbcOpZGljbyBlIGltcGxhbnRlLiIsCiAgICAiY29udGV4dG9fc29jaW9mYW1pbGlhciI6ICJMYSBtYWRyZSBlcyByZXNwb25zYWJsZSB5IHJlY2liZSBhcG95byBwYXJjaWFsIGRlbCBhYnVlbG8uIiwKICAgICJtYXBzX3VybF9tYW51YWwiOiAiaHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS9tYXBzL3NlYXJjaC8/YXBpPTEmcXVlcnk9Q2hhbGNvIiwKfQoKZmFtaWx5ID0gWwogICAgeyJub21icmUiOiAiSmFjb24gQWJkaWVsIiwgInBhcmVudGVzY28iOiAiU29saWNpdGFudGUiLCAiZWRhZCI6ICI1IiwgIm9jdXBhY2lvbiI6ICJFc3R1ZGlhbnRlIiwgInJlc3BvbnNhYmxlIjogRmFsc2V9LAogICAgeyJub21icmUiOiAiTWl4aSBOYXllbGxpIiwgInBhcmVudGVzY28iOiAiTWFkcmUiLCAiZWRhZCI6ICIzMyIsICJvY3VwYWNpb24iOiAiQ29tZXJjaWFudGUiLCAicmVzcG9uc2FibGUiOiBUcnVlfSwKICAgIHsibm9tYnJlIjogIlNhbnRpYWdvIiwgInBhcmVudGVzY28iOiAiQWJ1ZWxvIG1hdGVybm8iLCAiZWRhZCI6ICI1NiIsICJvY3VwYWNpb24iOiAiQ29tZXJjaWFudGUiLCAicmVzcG9uc2FibGUiOiBGYWxzZX0sCl0KCmluY29tZSA9IFsKICAgIHsiaW50ZWdyYW50ZSI6ICJNaXhpIE5heWVsbGkiLCAiaW5ncmVzb19tZW5zdWFsIjogIjcwMDAiLCAiYXBvcnRhY2lvbl9tZW5zdWFsIjogIjYxMDAifSwKICAgIHsiaW50ZWdyYW50ZSI6ICJTYW50aWFnbyIsICJpbmdyZXNvX21lbnN1YWwiOiAiOTAwMCIsICJhcG9ydGFjaW9uX21lbnN1YWwiOiAiMTUwMCJ9LApdCgpleHRyYXMgPSBbCiAgICB7ImNvbmNlcHRvIjogIlBhZ28gZGUgaW1wbGFudGUiLCAibW9udG9fbWVuc3VhbCI6ICI5MDAiLCAiZGV0YWxsZSI6ICJNZW5zdWFsaWRhZCB0ZW1wb3JhbCJ9LApdCgpjYWxjID0gY2FsY3VsYXRlX3JlZmVyZW5jZShkaWN0KGRhdGEpLCBmYW1pbHksIGluY29tZSwgZXh0cmFzKQpwcmludCgiUkVTUE9OU0FCTEVTOiIsIGNhbGNbInJlc3BvbnNpYmxlX21lbWJlcnMiXSkKcHJpbnQoIklOR1JFU086IiwgY2FsY1sidG90YWxfaW5jb21lIl0pCnByaW50KCJHQVNUTzoiLCBjYWxjWyJ0b3RhbF9leHBlbnNlcyJdKQpwcmludCgiRElTUE9OSUJMRToiLCBjYWxjWyJhdmFpbGFibGUiXSkKCmFzc2VydCBjYWxjWyJyZXNwb25zaWJsZV9tZW1iZXJzIl0gPT0gWyJNaXhpIE5heWVsbGkiXQphc3NlcnQgY2FsY1sicmVzcG9uc2libGVfY291bnQiXSA9PSAxCmFzc2VydCBjYWxjWyJob3VzZWhvbGRfc2l6ZSJdID09IDMKYXNzZXJ0IG1hcHNfc2VhcmNoX3VybChkYXRhKSA9PSBkYXRhWyJtYXBzX3VybF9tYW51YWwiXQoKY2xhc3MgU3R1ZHk6CiAgICBpZCA9IDEKICAgIGZvbGlvID0gIkVTLVRFU1QiCiAgICBzdHVkZW50X25hbWUgPSAiSmFjb24gQWJkaWVsIEd1dGllcnJleiBNb250YcOxbyIKICAgIHN0YXR1cyA9ICJGT1JNVUxBUklPIgoKd2l0aCBUZW1wb3JhcnlEaXJlY3RvcnkoKSBhcyB0bXA6CiAgICBzYXZlX2Zvcm0oCiAgICAgICAgdG1wLAogICAgICAgIDEsCiAgICAgICAgewogICAgICAgICAgICAiZGF0YSI6IGRhdGEsCiAgICAgICAgICAgICJmYW1pbHlfbWVtYmVycyI6IGZhbWlseSwKICAgICAgICAgICAgImluY29tZV9yb3dzIjogaW5jb21lLAogICAgICAgICAgICAiZXh0cmFfZXhwZW5zZXMiOiBleHRyYXMsCiAgICAgICAgfSwKICAgICkKCiAgICBleGNlbCA9IGJ1aWxkX2Nhc2VfZXhjZWwoU3R1ZHkoKSwgdG1wKQogICAgd2IgPSBsb2FkX3dvcmtib29rKGV4Y2VsKQogICAgYXNzZXJ0ICJSZXN1bWVuIiBpbiB3Yi5zaGVldG5hbWVzCiAgICBhc3NlcnQgIkFuYWxpc2lzX2Vjb25vbWljbyIgaW4gd2Iuc2hlZXRuYW1lcwoKICAgIHdzID0gd2JbIkFuYWxpc2lzX2Vjb25vbWljbyJdCiAgICBnYXN0b3MgPSBbXQogICAgZm9yIHJvdyBpbiByYW5nZSgyLCB3cy5tYXhfcm93ICsgMSk6CiAgICAgICAgbm9tYnJlID0gd3MuY2VsbChyb3csIDEpLnZhbHVlCiAgICAgICAgbW9udG8gPSB3cy5jZWxsKHJvdywgMikudmFsdWUKICAgICAgICBpZiBub21icmUgYW5kIGlzaW5zdGFuY2UobW9udG8sIChpbnQsIGZsb2F0KSk6CiAgICAgICAgICAgIGdhc3Rvcy5hcHBlbmQoKG5vbWJyZSwgbW9udG8pKQoKICAgIHByaW50KCJHQVNUT1NfRVhDRUw6IiwgZ2FzdG9zKQogICAgYXNzZXJ0IGdhc3RvcwogICAgYXNzZXJ0IGFsbChtb250byA+IDAgZm9yIF8sIG1vbnRvIGluIGdhc3RvcykKICAgIGFzc2VydCBub3QgYW55KG5vbWJyZSA9PSAiQXV0b23Ds3ZpbCIgZm9yIG5vbWJyZSwgXyBpbiBnYXN0b3MpCiAgICBhc3NlcnQgbm90IGFueShub21icmUgPT0gIkNvbGVnaWF0dXJhcyIgZm9yIG5vbWJyZSwgXyBpbiBnYXN0b3MpCiAgICBhc3NlcnQgYW55KG5vbWJyZSA9PSAiUGFnbyBkZSBpbXBsYW50ZSIgZm9yIG5vbWJyZSwgXyBpbiBnYXN0b3MpCgogICAgd29yZCA9IGJ1aWxkX2Nhc2Vfd29yZChTdHVkeSgpLCB0bXApCiAgICBkb2MgPSBEb2N1bWVudCh3b3JkKQogICAgdGV4dG8gPSAiXG4iLmpvaW4ocC50ZXh0IGZvciBwIGluIGRvYy5wYXJhZ3JhcGhzKQogICAgdGV4dG8gKz0gIlxuIiArICJcbiIuam9pbigKICAgICAgICBjZWxsLnRleHQKICAgICAgICBmb3IgdGFibGUgaW4gZG9jLnRhYmxlcwogICAgICAgIGZvciByb3cgaW4gdGFibGUucm93cwogICAgICAgIGZvciBjZWxsIGluIHJvdy5jZWxscwogICAgKQoKICAgIGZvciBleHBlY3RlZCBpbiAoCiAgICAgICAgIkZlY2hhIGRlIGVudHJldmlzdGEiLAogICAgICAgICJSZXNwb25zYWJsZSIsCiAgICAgICAgIk1peGkgTmF5ZWxsaSIsCiAgICAgICAgIlBhZ28gZGUgaW1wbGFudGUiLAogICAgICAgICJBc3BlY3RvcyBwYXJhIHJldmlzacOzbiBodW1hbmEiLAogICAgKToKICAgICAgICBhc3NlcnQgZXhwZWN0ZWQgaW4gdGV4dG8sIGV4cGVjdGVkCgpwcmludCgiVkFMSURBQ0lPTl9GVU5DSU9OQUxfT0siKQo="
$TestBytes = [Convert]::FromBase64String($TestBase64)
[IO.File]::WriteAllBytes($TestFile, $TestBytes)

python $TestFile
if ($LASTEXITCODE -eq 0) { OK "Word, Excel, responsables y gastos extra" } else { FAIL "Validacion funcional" }

python -c "from app import create_app; a=create_app(); r=a.test_client().get('/diagnostics/health'); print(r.status_code,r.get_json()); assert r.status_code==200"
if ($LASTEXITCODE -eq 0) { OK "Health" } else { FAIL "Health" }

Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue

Write-Host ""
git status --short
Write-Host ""

if ($Failures -eq 0) {
    Write-Host "VALIDACION PS37B: 0 FALLOS" -ForegroundColor Green
    Write-Host "Listo para prueba visual. TODAVIA NO HAGA COMMIT hasta revisarlo." -ForegroundColor Cyan
} else {
    Write-Host "VALIDACION PS37B: $Failures FALLO(S)" -ForegroundColor Red
    Write-Host "NO HAGA COMMIT." -ForegroundColor Red
    exit 1
}

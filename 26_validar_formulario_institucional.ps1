param([string]$ProjectPath=(Get-Location).Path)
$ErrorActionPreference="Continue";Set-Location $ProjectPath
Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS26 VALIDACION FORMULARIO INSTITUCIONAL" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
$Fails=0
function T($n,[scriptblock]$b){Write-Host "";Write-Host $n -ForegroundColor Cyan;try{&$b;if($LASTEXITCODE -and $LASTEXITCODE-ne0){throw "Codigo $LASTEXITCODE"};Write-Host "OK" -ForegroundColor Green}catch{$script:Fails++;Write-Host "FALLO: $($_.Exception.Message)" -ForegroundColor Red}}
T "[1] Rama main" {$x=(git branch --show-current).Trim();Write-Host $x;if($x-ne"main"){throw "Debe estar en main"}}
T "[2] Archivos" {foreach($f in @("app\routes\institutional_forms.py","app\services\institutional_form_service.py","app\services\institutional_export_service.py","app\templates\institutional_cases.html","app\templates\institutional_form.html","app\templates\institutional_preview.html")){if(!(Test-Path $f)){throw "Falta $f"};Write-Host $f}}
T "[3] Compilacion" {python -m compileall app -q}
T "[4] Rutas" {
@'
from app import create_app
a=create_app();routes={str(r) for r in a.url_map.iter_rules()}
req={"/estudios/","/estudios/nuevo","/estudios/<int:study_id>","/estudios/<int:study_id>/guardar","/estudios/<int:study_id>/preview","/estudios/<int:study_id>/excel","/estudios/<int:study_id>/word","/estudios/exportar/excel","/estudios/<int:study_id>/eliminar"}
print(sorted(r for r in routes if r.startswith("/estudios")))
m=req-routes
if m:raise SystemExit("Faltan "+",".join(sorted(m)))
'@ | Set-Content -Encoding ASCII "_tmp_ps26_routes.py";python "_tmp_ps26_routes.py";Remove-Item "_tmp_ps26_routes.py" -Force -ErrorAction SilentlyContinue
}
T "[5] Formulas" {
@'
from app.services.institutional_form_service import calculate_reference
d={"renta":"4500","luz":"600","agua":"350","telefono_gasto":"450","gas":"650","alimentos":"4000","pasajes":"1200","vestido":"600","medico_medicinas":"500","creditos_personales":"700","otros_gastos":"300","household_size":"3","total_ingresos":"15500"}
c=calculate_reference(d,[],[]);print(c)
assert c["total_income"]==15500.0
assert c["total_expenses"]==13850.0
assert c["available"]==1650.0
assert c["household_size"]==3
assert c["reference_fee"]>=0
'@ | Set-Content -Encoding ASCII "_tmp_ps26_formula.py";python "_tmp_ps26_formula.py";Remove-Item "_tmp_ps26_formula.py" -Force -ErrorAction SilentlyContinue
}
T "[6] Word + Excel" {
@'
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from app.services.institutional_form_service import save_form
from app.services.institutional_export_service import build_case_excel,build_case_word,build_bulk_excel
with TemporaryDirectory() as d:
 s=SimpleNamespace(id=1,folio="ES-TEST-001",student_name="Mateo Rios",status="FORMULARIO")
 save_form(d,1,{"data":{"nombre_alumno":"Mateo","apellido_paterno_alumno":"Rios","apellido_materno_alumno":"Luna","turno":"Matutino","calle":"Calle Prueba","numero":"123","colonia":"Centro","codigo_postal":"00000","estado":"CDMX","total_ingresos":"15500","renta":"4500","luz":"600","agua":"350","alimentos":"4000","pasajes":"1200","final_fee":"700","contexto_sociofamiliar":"Caso ficticio para validacion."},"family_members":[{"nombre":"Mateo","parentesco":"Alumno","edad":"8","ocupacion":"Estudiante"}],"income_rows":[{"integrante":"Madre","lugar_trabajo":"Comercio","antiguedad":"3 anos","puesto":"Ventas","ingreso_mensual":"15500","aportacion_mensual":"15500"}]})
 x=build_case_excel(s,d);w=build_case_word(s,d);b=build_bulk_excel([s],d)
 print(len(x.getvalue()),len(w.getvalue()),len(b.getvalue()))
 assert len(x.getvalue())>4000 and len(w.getvalue())>5000 and len(b.getvalue())>4000
'@ | Set-Content -Encoding ASCII "_tmp_ps26_exports.py";python "_tmp_ps26_exports.py";Remove-Item "_tmp_ps26_exports.py" -Force -ErrorAction SilentlyContinue
}
T "[7] Flujo visible limpio" {$m=Select-String -Path ".\app\templates\base.html",".\app\templates\index.html",".\app\templates\institutional_cases.html",".\app\templates\institutional_form.html" -Pattern "Revisión OCR|Revision OCR|Captura móvil|Captura movil|OpenCV|Prototipo" -ErrorAction SilentlyContinue;if($m){$m|Format-Table Path,LineNumber,Line -AutoSize;throw "Quedan textos del flujo anterior"}}
T "[8] Health" {
@'
from app import create_app
a=create_app();r=a.test_client().get("/diagnostics/health");print(r.status_code,r.get_json());assert r.status_code==200
'@ | Set-Content -Encoding ASCII "_tmp_ps26_health.py";python "_tmp_ps26_health.py";Remove-Item "_tmp_ps26_health.py" -Force -ErrorAction SilentlyContinue
}
Write-Host "";Write-Host "========================================================"
if($Fails-eq0){Write-Host " VALIDACION INSTITUCIONAL: 0 FALLOS" -ForegroundColor Green;Write-Host " Abra: http://127.0.0.1:5000/estudios/" -ForegroundColor Green}else{Write-Host " VALIDACION INSTITUCIONAL: $Fails FALLO(S)" -ForegroundColor Red;Write-Host " NO HAGA COMMIT." -ForegroundColor Red}
Write-Host "========================================================";exit $Fails

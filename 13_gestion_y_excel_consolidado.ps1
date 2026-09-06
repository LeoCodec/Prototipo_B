param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath
$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }
if ((git branch --show-current).Trim() -ne "main") { throw "Ejecutar en main." }

Write-Host "=== IPPLIAP PS13 - GESTION + EXCEL CONSOLIDADO ===" -ForegroundColor Green

@'
from __future__ import annotations
import statistics
from decimal import Decimal, InvalidOperation
from io import BytesIO
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
from app.services.report_service import field_payload
from app.services.socioeconomic_metrics import calculate_metrics

DARK="315500"; WHITE="FFFFFF"
EXPENSE_FIELDS=[("predial","Predial"),("renta","Renta"),("luz","Luz"),("agua","Agua"),("telefono_gasto","Teléfono"),("gas","Gas"),("alimentos","Alimentos"),("automovil","Automóvil"),("pasajes","Pasajes"),("colegiaturas","Colegiaturas"),("vestido","Vestido"),("medico_medicinas","Médico y medicinas"),("muebles_hogar","Muebles del hogar"),("creditos_personales","Créditos personales"),("otros_gastos","Otros gastos")]

def header(cell):
    cell.fill=PatternFill("solid",fgColor=DARK); cell.font=Font(color=WHITE,bold=True); cell.alignment=Alignment(horizontal="center")

def width(ws):
    for cells in ws.columns:
        i=cells[0].column; n=max(len(str(c.value or "")) for c in cells); ws.column_dimensions[get_column_letter(i)].width=min(max(n+2,10),48)

def number(value):
    if value is None: return None
    text=str(value).strip()
    if not text: return None
    low=text.lower()
    if any(x in low for x in ["ninguno","ninguna","no aplica"]): return 0.0
    raw=''.join(c for c in text if c.isdigit() or c in '.,-')
    if not raw: return None
    if ',' in raw and '.' in raw:
        raw=raw.replace(',','') if raw.rfind('.')>raw.rfind(',') else raw.replace('.','').replace(',','.')
    elif ',' in raw:
        p=raw.split(','); raw=''.join(p[:-1])+'.'+p[-1] if len(p[-1])==2 else raw.replace(',','')
    try: return float(Decimal(raw))
    except (InvalidOperation,ValueError): return None

def confirmed(payload,key):
    item=payload.get("fields",{}).get(key,{})
    return item.get("confirmed") or item.get("detected") or ""

def metrics_for(study,payload):
    data=payload.get("analysis",{})
    income=data.get("total_income",getattr(study,"total_income",0) or 0)
    expenses=data.get("total_expenses",getattr(study,"total_expenses",0) or 0)
    household=data.get("household_size",getattr(study,"household_size",1) or 1)
    fee=data.get("final_fee",getattr(study,"final_fee",None))
    return calculate_metrics(income,expenses,household),fee

def sheet_name(base,used):
    bad='[]:*?/\\'; name=''.join('_' if c in bad else c for c in base)[:31] or 'Caso'; original=name; n=2
    while name in used:
        suf=f'_{n}'; name=original[:31-len(suf)]+suf; n+=1
    used.add(name); return name

def build_bulk_workbook(studies,instance_path):
    wb=Workbook(); stats=wb.active; stats.title="Estadisticas"
    series={"Ingreso total":[],"Gasto total":[],"Cuota final":[]}
    for _,label in EXPENSE_FIELDS: series[label]=[]
    rows=[]
    for study in studies:
        payload=field_payload(instance_path,study.id); m,fee=metrics_for(study,payload); expenses={}
        series["Ingreso total"].append(m.total_income); series["Gasto total"].append(m.total_expenses)
        if fee is not None: series["Cuota final"].append(float(fee))
        for key,label in EXPENSE_FIELDS:
            v=number(confirmed(payload,key)); expenses[key]=v
            if v is not None: series[label].append(v)
        rows.append((study,payload,m,fee,expenses))
    for c,h in enumerate(["Indicador","Casos con dato","Media","Mediana","Mínimo","Máximo"],1): stats.cell(1,c,h); header(stats.cell(1,c))
    r=2
    for label,values in series.items():
        stats.cell(r,1,label); stats.cell(r,2,len(values))
        if values:
            vals=[round(statistics.mean(values),2),round(statistics.median(values),2),round(min(values),2),round(max(values),2)]
            for c,v in enumerate(vals,3): stats.cell(r,c,v); stats.cell(r,c).number_format='$#,##0.00 "MXN"'
        r+=1
    cases=wb.create_sheet("Casos")
    headers=["Folio","Caso","Estatus","Turno","Ingreso total","Gasto total","Disponible","Integrantes","Ingreso per cápita","Disponible per cápita","Carga de gasto (%)","Cuota final"]+[x[1] for x in EXPENSE_FIELDS]
    for c,h in enumerate(headers,1): cases.cell(1,c,h); header(cases.cell(1,c))
    for r,(study,payload,m,fee,expenses) in enumerate(rows,2):
        values=[study.folio,study.student_name,study.status,confirmed(payload,"turno"),m.total_income,m.total_expenses,m.available,m.household_size,m.income_per_capita,m.available_per_capita,m.expense_burden_pct,fee if fee is not None else ""]+[expenses[k] if expenses[k] is not None else "" for k,_ in EXPENSE_FIELDS]
        for c,v in enumerate(values,1): cases.cell(r,c,v)
    used={"Estadisticas","Casos"}
    for study,payload,m,fee,expenses in rows:
        ws=wb.create_sheet(sheet_name(f"Caso_{study.id}_{study.student_name}",used)); ws["A1"]=f"{study.folio} - {study.student_name}"; ws["A1"].font=Font(size=14,bold=True,color=DARK); ws.merge_cells("A1:D1")
        summary=[("Ingreso total",m.total_income),("Gasto total",m.total_expenses),("Disponible",m.available),("Integrantes",m.household_size),("Ingreso per cápita",m.income_per_capita),("Disponible per cápita",m.available_per_capita),("Carga de gasto (%)",m.expense_burden_pct),("Cuota final",fee if fee is not None else ""),("Contexto humano",payload.get("context_notes",""))]
        for rr,(lab,val) in enumerate(summary,3): ws.cell(rr,1,lab).font=Font(bold=True,color=DARK); ws.cell(rr,2,val)
        start=14
        for c,h in enumerate(["Campo","OCR","Confirmado","Confianza"],1): ws.cell(start,c,h); header(ws.cell(start,c))
        for rr,(name,item) in enumerate(payload.get("fields",{}).items(),start+1):
            ws.cell(rr,1,item.get("label") or name); ws.cell(rr,2,item.get("raw_detected") or item.get("detected") or ""); ws.cell(rr,3,item.get("confirmed") or ""); ws.cell(rr,4,round(float(item.get("confidence",0))*100,2))
    for ws in wb.worksheets: ws.freeze_panes="A2"; width(ws)
    out=BytesIO(); wb.save(out); out.seek(0); return out
'@ | Set-Content -Encoding UTF8 "app\services\bulk_report_service.py"

@'
from pathlib import Path
from flask import Blueprint,current_app,flash,redirect,render_template,request,url_for
from app.extensions import db
from app.models.study import Study
from app.services.activity_service import record_event

case_management_bp=Blueprint("case_management",__name__,url_prefix="/cases")

def delete_case(study):
    root=Path(current_app.root_path).parent; uploads=Path(current_app.config.get("UPLOAD_FOLDER") or root/"uploads")
    for image in list(study.images):
        filename=getattr(image,"filename","")
        if filename:
            direct=uploads/filename
            target=direct if direct.exists() else (next(uploads.rglob(filename),None) if uploads.exists() else None)
            if target and target.exists():
                try: target.unlink()
                except OSError: pass
        db.session.delete(image)
    aux=Path(current_app.instance_path)/"field_extractions"/f"study_{study.id}.json"
    if aux.exists():
        try: aux.unlink()
        except OSError: pass
    db.session.delete(study)

@case_management_bp.get("/manage")
def manage(): return render_template("cases_manage.html",studies=Study.query.order_by(Study.id.desc()).all())

@case_management_bp.post("/bulk-delete")
def bulk_delete():
    ids=[int(x) for x in request.form.getlist("study_ids") if x.isdigit()]
    if not ids: flash("Seleccione al menos un caso.","warning"); return redirect(url_for("case_management.manage"))
    studies=Study.query.filter(Study.id.in_(ids)).all()
    for study in studies: record_event("study_deleted",study.id); delete_case(study)
    db.session.commit(); flash(f"Se eliminaron {len(studies)} caso(s) y sus archivos asociados.","success"); return redirect(url_for("case_management.manage"))
'@ | Set-Content -Encoding UTF8 "app\routes\case_management.py"

@'
{% extends "base.html" %}{% block title %}Administrar casos{% endblock %}{% block page_name %}Administrar casos{% endblock %}{% block content %}
<section class="page-title-card"><div><span class="eyebrow">GESTI&Oacute;N DEL PILOTO</span><h1>Casos registrados</h1><p>Seleccione expedientes para exportarlos o eliminarlos.</p></div></section>
<div class="notice-card"><i class="bi bi-shield-check notice-icon"></i><div><strong>Minimizaci&oacute;n de datos.</strong><p>Elimine expedientes de prueba que ya no sean necesarios.</p></div></div>
<form method="POST"><section class="section"><div class="review-card"><div class="bottom-actions" style="justify-content:flex-end;margin-bottom:16px"><button class="btn btn-primary" formaction="{{ url_for('reports.bulk_excel') }}" type="submit"><i class="bi bi-file-earmark-excel"></i> Excel consolidado</button><button class="btn" formaction="{{ url_for('case_management.bulk_delete') }}" type="submit" onclick="return confirm('¿Eliminar definitivamente los casos seleccionados y sus archivos?');"><i class="bi bi-trash"></i> Eliminar seleccionados</button></div><div style="overflow:auto"><table style="width:100%;border-collapse:collapse"><thead><tr><th><input type="checkbox" id="select-all"></th><th>Folio</th><th>Caso</th><th>Estatus</th><th>Acciones</th></tr></thead><tbody>{% for study in studies %}<tr><td><input class="case-check" type="checkbox" name="study_ids" value="{{ study.id }}"></td><td>{{ study.folio }}</td><td>{{ study.student_name }}</td><td>{{ study.status }}</td><td><a class="btn" href="{{ url_for('main.study_detail',study_id=study.id) }}">Detalle</a><a class="btn" href="{{ url_for('fields.detected',study_id=study.id) }}">Campos</a><a class="btn" href="{{ url_for('analysis.study',study_id=study.id) }}">Indicadores</a></td></tr>{% else %}<tr><td colspan="5">No hay casos registrados.</td></tr>{% endfor %}</tbody></table></div></div></section></form>
<script>const m=document.getElementById('select-all');if(m){m.addEventListener('change',()=>document.querySelectorAll('.case-check').forEach(e=>e.checked=m.checked));}</script>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\cases_manage.html"

$patch = @'
from pathlib import Path
import re
p=Path("app/routes/reports.py"); text=p.read_text(encoding="utf-8")
if "from app.services.bulk_report_service import build_bulk_workbook" not in text:
    anchor="from app.services.word_report_service import build_case_docx"
    if anchor in text: text=text.replace(anchor,anchor+"\nfrom app.services.bulk_report_service import build_bulk_workbook")
text=text.replace("output = bulk_workbook(\n        studies,\n        current_app.instance_path,\n    )","output = build_bulk_workbook(\n        studies,\n        current_app.instance_path,\n    )")
p.write_text(text,encoding="utf-8")

p=Path("app/__init__.py"); text=p.read_text(encoding="utf-8")
if "app.register_blueprint(case_management_bp)" not in text:
    ms=list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$",text)); m=ms[-1]; ind=m.group(1)
    ins=f"{ind}from app.routes.case_management import case_management_bp\n{ind}app.register_blueprint(case_management_bp)\n\n"
    text=text[:m.start()]+ins+text[m.start():]; p.write_text(text,encoding="utf-8")

p=Path("app/templates/index.html")
if p.exists():
    text=p.read_text(encoding="utf-8"); marker="<!-- PS13-ADMIN -->"
    if marker not in text:
        snippet='''\n<!-- PS13-ADMIN -->\n<section class="section"><div class="bottom-actions" style="justify-content:flex-end"><a class="btn" href="{{ url_for('case_management.manage') }}">Seleccionar / administrar casos</a><a class="btn btn-primary" href="{{ url_for('reports.index') }}">Reportes</a></div></section>\n'''
        pos=text.rfind("{% endblock %}")
        if pos!=-1: text=text[:pos]+snippet+text[pos:]; p.write_text(text,encoding="utf-8")
'@
$tmp=Join-Path $env:TEMP "ps13_patch.py"; $patch|Set-Content -Encoding UTF8 $tmp; & $Py $tmp; Remove-Item $tmp -Force

& $Py -m compileall app -q
& $Py -c "from app import create_app; a=create_app(); print([str(r) for r in a.url_map.iter_rules() if '/cases' in str(r)])"
Write-Host "PS13 listo: http://127.0.0.1:5000/cases/manage" -ForegroundColor Green

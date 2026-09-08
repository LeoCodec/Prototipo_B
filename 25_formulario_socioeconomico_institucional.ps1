param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
Set-Location $ProjectPath

Write-Host "========================================================" -ForegroundColor Green
Write-Host " IPPLIAP - PS25 FORMULARIO SOCIOECONOMICO INSTITUCIONAL" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green

if (-not (Test-Path ".\app\__init__.py")) {
    throw "Ejecute este script desde la raiz de Prototipo_B."
}

$Branch = (git branch --show-current).Trim()
Write-Host "Rama actual: $Branch" -ForegroundColor Cyan
if ($Branch -ne "main") {
    throw "La rama activa debe ser main."
}

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Backup = Join-Path $ProjectPath "backup_pre_formulario_$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null

$FilesToBackup = @(
    "app\__init__.py",
    "app\templates\base.html",
    "app\templates\index.html",
    ".env.example"
)

foreach ($f in $FilesToBackup) {
    if (Test-Path $f) {
        $dest = Join-Path $Backup $f
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item $f $dest -Force
    }
}
Write-Host "Backup previo: $Backup" -ForegroundColor Yellow

$Patch = @'
from pathlib import Path
import re

root = Path.cwd()

def write_ascii(path, text):
    p = root / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="ascii", newline="\n")

def write_utf8(path, text):
    p = root / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="\n")

write_ascii("app/services/institutional_form_service.py", r'''from __future__ import annotations
import json, os
from datetime import datetime
from pathlib import Path
from urllib.parse import quote_plus

ANNUAL_EXPENSE_FIELDS=("predial_anual","gastos_anuales","vacaciones_anual")
MONTHLY_EXPENSE_FIELDS=("renta","luz","agua","telefono_gasto","gas","alimentos","automovil","pasajes","colegiaturas","vestido","medico_medicinas","muebles_hogar","creditos_personales","otros_gastos")

def _file(instance_path,study_id):
    p=Path(instance_path)/"institutional_forms";p.mkdir(parents=True,exist_ok=True)
    return p/f"study_{study_id}.json"

def _number(value,default=0.0):
    if value is None:return default
    t=str(value).strip()
    if not t:return default
    t=t.replace("$","").replace("MXN","").replace(" ","")
    if "," in t and "." in t:
        t=t.replace(",","") if t.rfind(".")>t.rfind(",") else t.replace(".","").replace(",",".")
    elif "," in t:
        parts=t.split(",");t="".join(parts[:-1])+"."+parts[-1] if len(parts[-1])==2 else t.replace(",","")
    try:return float(t)
    except:return default

def load_form(instance_path,study_id):
    p=_file(instance_path,study_id)
    if not p.exists():
        return {"study_id":study_id,"data":{},"family_members":[],"income_rows":[],"calculation":{},"updated_at":None}
    try:d=json.loads(p.read_text(encoding="utf-8"))
    except:d={}
    d.setdefault("study_id",study_id);d.setdefault("data",{});d.setdefault("family_members",[]);d.setdefault("income_rows",[]);d.setdefault("calculation",{});d.setdefault("updated_at",None)
    return d

def _income_total(data,rows):
    explicit=_number(data.get("total_ingresos"),None)
    if explicit is not None:return max(explicit,0.0)
    total=0.0
    for r in rows:
        v=_number(r.get("aportacion_mensual"),None)
        if v is None:v=_number(r.get("ingreso_mensual"),0.0)
        total+=max(v or 0.0,0.0)
    return total

def _expenses_monthly(data):
    total=0.0;detail={}
    for k in MONTHLY_EXPENSE_FIELDS:
        v=max(_number(data.get(k),0.0),0.0);detail[k]=v;total+=v
    for k in ANNUAL_EXPENSE_FIELDS:
        a=max(_number(data.get(k),0.0),0.0);m=a/12.0;detail[k]=a;detail[k+"_mensual_equiv"]=m;total+=m
    return total,detail

def calculate_reference(data,family_members=None,income_rows=None):
    family_members=family_members or [];income_rows=income_rows or []
    income=_income_total(data,income_rows);expenses,detail=_expenses_monthly(data);available=income-expenses
    try:n=int(float(data.get("household_size") or len(family_members) or 1))
    except:n=len(family_members) or 1
    n=max(n,1)
    ipc=income/n;dpc=available/n;burden=(expenses/income*100.0) if income>0 else 0.0
    max_fee=max(_number(os.getenv("MAX_REFERENCE_FEE","4500"),4500.0),0.0)
    income_ratio=max(_number(os.getenv("FEE_INCOME_RATIO","0.08"),0.08),0.0)
    disposable_ratio=max(_number(os.getenv("FEE_DISPOSABLE_RATIO","0.20"),0.20),0.0)
    scholarship=min(max(_number(data.get("beca_actual_pct"),0.0),0.0),100.0)
    scholarship_cap=max_fee*(1.0-scholarship/100.0)
    raw=0.0 if income<=0 or available<=0 else min(max_fee,scholarship_cap,income*income_ratio,available*disposable_ratio)
    ref=round(raw/50.0)*50.0 if raw>0 else 0.0
    ref=min(max(ref,0.0),scholarship_cap,max_fee)
    final=_number(data.get("final_fee"),None)
    if income<=0:explanation="No se calcula una cuota de referencia porque no hay ingreso mensual confirmado."
    elif available<=0:explanation="La disponibilidad mensual es igual o menor que cero; la cuota de referencia es $0.00 MXN."
    else:explanation="La cuota de referencia toma el menor limite entre el tope configurado, un porcentaje del ingreso y un porcentaje de la disponibilidad. Es orientativa y no sustituye la valoracion institucional."
    return {"total_income":round(income,2),"total_expenses":round(expenses,2),"available":round(available,2),"household_size":n,"income_per_capita":round(ipc,2),"available_per_capita":round(dpc,2),"expense_burden_pct":round(burden,2),"reference_fee":round(ref,2),"final_fee":None if final is None else round(final,2),"max_reference_fee":round(max_fee,2),"income_ratio":income_ratio,"disposable_ratio":disposable_ratio,"scholarship_pct":scholarship,"scholarship_cap":round(scholarship_cap,2),"expense_detail":detail,"explanation":explanation}

def full_address(data):
    direct=str(data.get("domicilio") or "").strip()
    if direct:return direct
    parts=[data.get("calle"),data.get("numero"),data.get("colonia"),data.get("codigo_postal"),data.get("estado")]
    return ", ".join(str(x).strip() for x in parts if str(x or "").strip())

def maps_search_url(data):
    a=full_address(data)
    return "" if not a else "https://www.google.com/maps/search/?api=1&query="+quote_plus(a)

def maps_static_url(data):
    key=str(os.getenv("GOOGLE_MAPS_API_KEY") or "").strip();a=full_address(data)
    if not key or not a:return ""
    return "https://maps.googleapis.com/maps/api/staticmap?center="+quote_plus(a)+"&zoom=18&size=640x360&maptype=roadmap&markers=color:red%7C"+quote_plus(a)+"&key="+quote_plus(key)

def save_form(instance_path,study_id,body):
    data=dict(body.get("data") or {});family=list(body.get("family_members") or []);rows=list(body.get("income_rows") or [])
    if not str(data.get("domicilio") or "").strip():data["domicilio"]=full_address(data)
    calc=calculate_reference(data,family,rows)
    payload={"study_id":study_id,"data":data,"family_members":family,"income_rows":rows,"calculation":calc,"maps_url":maps_search_url(data),"maps_static_url":maps_static_url(data),"updated_at":datetime.now().isoformat(timespec="seconds")}
    _file(instance_path,study_id).write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding="utf-8")
    return payload

def delete_form(instance_path,study_id):
    p=_file(instance_path,study_id)
    if p.exists():p.unlink()
''')

write_ascii("app/services/institutional_export_service.py", r'''from __future__ import annotations
from io import BytesIO
from statistics import mean,median
import re
from openpyxl import Workbook
from openpyxl.styles import Alignment,Font,PatternFill
from openpyxl.utils import get_column_letter
from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from app.services.institutional_form_service import load_form

GREEN="2E5D0B";WHITE="FFFFFF"
LABELS={"solicitud_tipo":"Tipo de solicitud","turno":"Turno","grado":"Grado que solicita","fecha":"Fecha","nombre_alumno":"Nombre","apellido_paterno_alumno":"Apellido paterno","apellido_materno_alumno":"Apellido materno","fecha_nacimiento":"Fecha de nacimiento","edad":"Edad","domicilio":"Domicilio","telefono":"Tel\u00e9fono","celular":"Celular","solicitante_nombre":"Nombre de quien solicita","solicitante_parentesco":"Parentesco","solicitante_edad":"Edad del solicitante","solicitante_domicilio":"Domicilio del solicitante","solicitante_telefono":"Tel\u00e9fono","solicitante_celular":"Celular","solicitante_escolaridad":"Escolaridad","solicitante_ocupacion":"Ocupaci\u00f3n","solicitante_trabajo":"Nombre y domicilio del trabajo","solicitante_trabajo_telefono":"Tel\u00e9fono de trabajo","solicitante_correo":"Correo electr\u00f3nico","razon_apoyo":"Raz\u00f3n de solicitud","vivienda_tenencia":"Tenencia de vivienda","vivienda_tipo":"Tipo de vivienda","habitaciones":"Habitaciones","dormitorios":"Dormitorios","espacios_vivienda":"Espacios","paredes":"Paredes","techos":"Techos","pisos":"Pisos","servicios_vivienda":"Servicios","bienes_hogar":"Bienes del hogar","zona":"Caracter\u00edsticas de la zona","comunidad":"Servicios/comunidad","transporte":"Transporte","transporte_modelo":"Modelo","transporte_anio":"A\u00f1o","referencias":"Referencias","beca_actual_pct":"Beca actual (%)","predial_anual":"Predial anual","gastos_anuales":"Otros gastos anuales","vacaciones_anual":"Vacaciones anual","renta":"Renta mensual","luz":"Luz mensual","agua":"Agua mensual","telefono_gasto":"Tel\u00e9fono mensual","gas":"Gas mensual","alimentos":"Alimentos mensual","automovil":"Autom\u00f3vil mensual","pasajes":"Pasajes mensual","colegiaturas":"Colegiaturas mensual","vestido":"Vestido mensual","medico_medicinas":"M\u00e9dico y medicinas mensual","muebles_hogar":"Muebles del hogar mensual","creditos_personales":"Cr\u00e9ditos personales mensual","otros_gastos":"Otros gastos mensual","servicio_medico":"Servicio m\u00e9dico","enfermedades_cronicas":"Enfermedades cr\u00f3nicas","tiempo_libre":"Tiempo libre","observaciones":"Observaciones","contexto_sociofamiliar":"Contexto sociofamiliar","final_fee":"Cuota final autorizada"}

def money(v):
    if v is None or v=="":return "Pendiente"
    try:return "$ {:,.2f} MXN".format(float(v))
    except:return str(v)

def _safe(t):return (re.sub(r"[^A-Za-z0-9_-]+","_",str(t or "").strip())[:28] or "Caso")

def _header(ws,row,cols):
    for c,v in enumerate(cols,1):
        x=ws.cell(row=row,column=c,value=v);x.fill=PatternFill("solid",fgColor=GREEN);x.font=Font(color=WHITE,bold=True);x.alignment=Alignment(horizontal="center",vertical="center",wrap_text=True)

def _fit(ws):
    for c in range(1,ws.max_column+1):
        w=12
        for r in range(1,min(ws.max_row,120)+1):
            v=ws.cell(r,c).value
            if v is not None:w=max(w,min(len(str(v))+2,42))
        ws.column_dimensions[get_column_letter(c)].width=w

def _section(wb,title,pairs):
    ws=wb.create_sheet(title);_header(ws,1,["Campo","Valor"]);r=2
    for a,b in pairs:ws.cell(r,1,a);ws.cell(r,2,b);r+=1
    ws.freeze_panes="A2";_fit(ws);return ws

def _link(paragraph,text,url):
    rid=paragraph.part.relate_to(url,"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",is_external=True)
    h=OxmlElement("w:hyperlink");h.set(qn("r:id"),rid);run=OxmlElement("w:r");rpr=OxmlElement("w:rPr");color=OxmlElement("w:color");color.set(qn("w:val"),"0563C1");u=OxmlElement("w:u");u.set(qn("w:val"),"single");rpr.append(color);rpr.append(u);run.append(rpr);t=OxmlElement("w:t");t.text=text;run.append(t);h.append(run);paragraph._p.append(h)

def _doc_table(doc,rows,headers=("Campo","Valor")):
    t=doc.add_table(rows=1,cols=2);t.style="Table Grid";t.rows[0].cells[0].text=headers[0];t.rows[0].cells[1].text=headers[1]
    for a,b in rows:
        if b in (None,""):continue
        c=t.add_row().cells;c[0].text=str(a);c[1].text=str(b)
    return t

def payload(study,instance_path):
    p=load_form(instance_path,study.id);return p,p.get("data",{}),p.get("calculation",{})

def build_case_excel(study,instance_path):
    p,d,c=payload(study,instance_path);wb=Workbook();ws=wb.active;ws.title="Resumen"
    ws["A1"]="IPPLIAP - Estudio socioecon\u00f3mico";ws["A1"].font=Font(size=16,bold=True,color=GREEN);ws.merge_cells("A1:D1")
    _header(ws,3,["Indicador","Resultado"])
    rows=[("Folio",study.folio),("Caso",study.student_name),("Estatus",study.status),("Turno",d.get("turno","")),("Ingreso total",c.get("total_income",0)),("Gasto mensual equivalente",c.get("total_expenses",0)),("Disponible",c.get("available",0)),("Integrantes",c.get("household_size",1)),("Ingreso per c\u00e1pita",c.get("income_per_capita",0)),("Disponible per c\u00e1pita",c.get("available_per_capita",0)),("Carga de gasto (%)",c.get("expense_burden_pct",0)),("Cuota de referencia",c.get("reference_fee",0)),("Cuota final autorizada",c.get("final_fee"))]
    money_labels={"Ingreso total","Gasto mensual equivalente","Disponible","Ingreso per c\u00e1pita","Disponible per c\u00e1pita","Cuota de referencia","Cuota final autorizada"}
    r=4
    for a,b in rows:
        ws.cell(r,1,a);ws.cell(r,2,b)
        if a in money_labels and b not in (None,""):ws.cell(r,2).number_format='$#,##0.00 "MXN"'
        r+=1
    maps=p.get("maps_url") or "";ws.cell(r+1,1,"Google Maps (referencia)");ws.cell(r+1,2,"Abrir ubicaci\u00f3n")
    if maps:ws.cell(r+1,2).hyperlink=maps;ws.cell(r+1,2).style="Hyperlink"
    _fit(ws)

    akeys=["solicitud_tipo","turno","grado","fecha","nombre_alumno","apellido_paterno_alumno","apellido_materno_alumno","fecha_nacimiento","edad","domicilio","telefono","celular"]
    _section(wb,"Alumno",[(LABELS[k],d.get(k,"")) for k in akeys])
    skeys=["solicitante_nombre","solicitante_parentesco","solicitante_edad","solicitante_domicilio","solicitante_telefono","solicitante_celular","solicitante_escolaridad","solicitante_ocupacion","solicitante_trabajo","solicitante_trabajo_telefono","solicitante_correo","razon_apoyo"]
    _section(wb,"Solicitante",[(LABELS[k],d.get(k,"")) for k in skeys])

    f=wb.create_sheet("Familia");_header(f,1,["Nombre","Parentesco","Edad","Ocupaci\u00f3n"])
    for i,row in enumerate(p.get("family_members") or [],2):
        for col,key in enumerate(("nombre","parentesco","edad","ocupacion"),1):f.cell(i,col,row.get(key,""))
    _fit(f)

    vkeys=["vivienda_tenencia","vivienda_tipo","habitaciones","dormitorios","espacios_vivienda","paredes","techos","pisos","servicios_vivienda","bienes_hogar","zona","comunidad","transporte","transporte_modelo","transporte_anio","referencias"]
    v=_section(wb,"Vivienda",[(LABELS[k],d.get(k,"")) for k in vkeys]);rr=v.max_row+2;v.cell(rr,1,"Google Maps");v.cell(rr,2,"Abrir ubicaci\u00f3n")
    if maps:v.cell(rr,2).hyperlink=maps;v.cell(rr,2).style="Hyperlink"

    inc=wb.create_sheet("Ingresos");_header(inc,1,["Integrante","Lugar de trabajo","Antig\u00fcedad","Puesto","Ingreso mensual","Aportaci\u00f3n mensual"])
    for i,row in enumerate(p.get("income_rows") or [],2):
        vals=[row.get("integrante",""),row.get("lugar_trabajo",""),row.get("antiguedad",""),row.get("puesto",""),row.get("ingreso_mensual",""),row.get("aportacion_mensual","")]
        for col,val in enumerate(vals,1):inc.cell(i,col,val)
        inc.cell(i,5).number_format='$#,##0.00 "MXN"';inc.cell(i,6).number_format='$#,##0.00 "MXN"'
    _fit(inc)

    ekeys=["predial_anual","gastos_anuales","vacaciones_anual","renta","luz","agua","telefono_gasto","gas","alimentos","automovil","pasajes","colegiaturas","vestido","medico_medicinas","muebles_hogar","creditos_personales","otros_gastos"]
    g=_section(wb,"Gastos",[(LABELS[k],d.get(k,"")) for k in ekeys])
    for cell in g["B"][1:]:
        if cell.value not in (None,""):
            try:cell.value=float(cell.value);cell.number_format='$#,##0.00 "MXN"'
            except:pass

    ckeys=["servicio_medico","enfermedades_cronicas","tiempo_libre","observaciones","contexto_sociofamiliar","beca_actual_pct"]
    _section(wb,"Salud_Contexto",[(LABELS[k],d.get(k,"")) for k in ckeys])

    ind=wb.create_sheet("Indicadores");_header(ind,1,["Indicador","Resultado"])
    ir=[("Ingreso total",c.get("total_income",0)),("Gasto mensual equivalente",c.get("total_expenses",0)),("Disponible",c.get("available",0)),("Integrantes del hogar",c.get("household_size",1)),("Ingreso per c\u00e1pita",c.get("income_per_capita",0)),("Disponible per c\u00e1pita",c.get("available_per_capita",0)),("Carga de gasto (%)",c.get("expense_burden_pct",0)),("Cuota de referencia",c.get("reference_fee",0)),("Cuota final autorizada",c.get("final_fee")),("Explicaci\u00f3n",c.get("explanation",""))]
    for i,(a,b) in enumerate(ir,2):ind.cell(i,1,a);ind.cell(i,2,b)
    _fit(ind)

    out=BytesIO();wb.save(out);out.seek(0);return out

def build_case_word(study,instance_path):
    p,d,c=payload(study,instance_path);doc=Document();doc.styles["Normal"].font.name="Arial";doc.styles["Normal"].font.size=Pt(10)
    title=doc.add_paragraph();title.alignment=WD_ALIGN_PARAGRAPH.CENTER;r=title.add_run("ESTUDIO SOCIOECON\u00d3MICO");r.bold=True;r.font.size=Pt(18)
    sub=doc.add_paragraph();sub.alignment=WD_ALIGN_PARAGRAPH.CENTER;sub.add_run("Instituto Pedag\u00f3gico para Problemas del Lenguaje, I.A.P.").bold=True
    doc.add_paragraph("Folio: "+str(study.folio));doc.add_paragraph("Caso: "+str(study.student_name));doc.add_paragraph("Estatus: "+str(study.status))

    doc.add_heading("1. Datos generales del alumno",1);akeys=["solicitud_tipo","turno","grado","fecha","nombre_alumno","apellido_paterno_alumno","apellido_materno_alumno","fecha_nacimiento","edad","domicilio","telefono","celular"];_doc_table(doc,[(LABELS[k],d.get(k,"")) for k in akeys])
    maps=p.get("maps_url") or ""
    if maps:
        par=doc.add_paragraph("Ubicaci\u00f3n de referencia: ");_link(par,"Abrir en Google Maps",maps)
        doc.add_paragraph("La ubicaci\u00f3n es aproximada y no confirma por s\u00ed sola la vivienda.")

    doc.add_heading("2. Datos de quien solicita la beca",1);skeys=["solicitante_nombre","solicitante_parentesco","solicitante_edad","solicitante_domicilio","solicitante_telefono","solicitante_celular","solicitante_escolaridad","solicitante_ocupacion","solicitante_trabajo","solicitante_trabajo_telefono","solicitante_correo","razon_apoyo"];_doc_table(doc,[(LABELS[k],d.get(k,"")) for k in skeys])

    doc.add_heading("3. Integrantes del hogar",1);fam=p.get("family_members") or []
    if fam:
        t=doc.add_table(rows=1,cols=4);t.style="Table Grid"
        for i,x in enumerate(("Nombre","Parentesco","Edad","Ocupaci\u00f3n")):t.rows[0].cells[i].text=x
        for row in fam:
            cc=t.add_row().cells
            for i,key in enumerate(("nombre","parentesco","edad","ocupacion")):cc[i].text=str(row.get(key,""))
    else:doc.add_paragraph("Sin integrantes registrados.")

    doc.add_heading("4. Vivienda",1);vkeys=["vivienda_tenencia","vivienda_tipo","habitaciones","dormitorios","espacios_vivienda","paredes","techos","pisos","servicios_vivienda","bienes_hogar","zona","comunidad","transporte","transporte_modelo","transporte_anio","referencias"];_doc_table(doc,[(LABELS[k],d.get(k,"")) for k in vkeys])

    doc.add_heading("5. Situaci\u00f3n econ\u00f3mica",1);rows=p.get("income_rows") or []
    if rows:
        t=doc.add_table(rows=1,cols=6);t.style="Table Grid"
        for i,x in enumerate(("Integrante","Lugar de trabajo","Antig\u00fcedad","Puesto","Ingreso","Aportaci\u00f3n")):t.rows[0].cells[i].text=x
        for row in rows:
            cc=t.add_row().cells;vals=[row.get("integrante",""),row.get("lugar_trabajo",""),row.get("antiguedad",""),row.get("puesto",""),money(row.get("ingreso_mensual")),money(row.get("aportacion_mensual"))]
            for i,v in enumerate(vals):cc[i].text=str(v)
    doc.add_paragraph("Ingreso mensual considerado: "+money(c.get("total_income",0)))

    doc.add_heading("6. Distribuci\u00f3n del gasto familiar",1);ekeys=["predial_anual","gastos_anuales","vacaciones_anual","renta","luz","agua","telefono_gasto","gas","alimentos","automovil","pasajes","colegiaturas","vestido","medico_medicinas","muebles_hogar","creditos_personales","otros_gastos"];_doc_table(doc,[(LABELS[k],money(d.get(k)) if d.get(k) not in (None,"") else "") for k in ekeys])

    doc.add_heading("7. Salud y contexto",1);ckeys=["servicio_medico","enfermedades_cronicas","tiempo_libre","observaciones","contexto_sociofamiliar","beca_actual_pct"];_doc_table(doc,[(LABELS[k],d.get(k,"")) for k in ckeys])

    doc.add_heading("8. Indicadores socioecon\u00f3micos",1);_doc_table(doc,[("Ingreso total",money(c.get("total_income",0))),("Gasto mensual equivalente",money(c.get("total_expenses",0))),("Disponible",money(c.get("available",0))),("Integrantes del hogar",c.get("household_size",1)),("Ingreso per c\u00e1pita",money(c.get("income_per_capita",0))),("Disponible per c\u00e1pita",money(c.get("available_per_capita",0))),("Carga de gasto",str(c.get("expense_burden_pct",0))+" %")],("Indicador","Resultado"))

    doc.add_heading("9. Cuota de referencia y valoraci\u00f3n",1);_doc_table(doc,[("Cuota de referencia calculada",money(c.get("reference_fee",0))),("Cuota final autorizada",money(c.get("final_fee")))],("Concepto","Resultado"));doc.add_paragraph(str(c.get("explanation","")));doc.add_paragraph("La cuota de referencia es orientativa. La cuota final debe ser revisada y autorizada por el personal institucional responsable.")

    doc.add_heading("10. Alcance",1);doc.add_paragraph("Este documento resume la informaci\u00f3n capturada manualmente en el formulario digital. No sustituye la entrevista, la observaci\u00f3n profesional ni la decisi\u00f3n institucional final.")
    out=BytesIO();doc.save(out);out.seek(0);return out

def _metric(vals):
    vals=[float(v) for v in vals if v is not None]
    return (0,None,None,None,None) if not vals else (len(vals),mean(vals),median(vals),min(vals),max(vals))

def build_bulk_excel(studies,instance_path):
    wb=Workbook();stats=wb.active;stats.title="Estad\u00edsticas";cases=wb.create_sheet("Casos");records=[(s,*payload(s,instance_path)) for s in studies]
    _header(stats,1,["Indicador","Casos con dato","Media","Mediana","M\u00ednimo","M\u00e1ximo"])
    defs=[("Ingreso total","total_income"),("Gasto mensual equivalente","total_expenses"),("Disponible","available"),("Cuota de referencia","reference_fee"),("Cuota final autorizada","final_fee")]
    for i,(label,key) in enumerate(defs,2):
        count,avg,med,mn,mx=_metric([c.get(key) for _,_,_,c in records]);stats.cell(i,1,label);stats.cell(i,2,count)
        for col,v in enumerate((avg,med,mn,mx),3):
            stats.cell(i,col,v)
            if v is not None:stats.cell(i,col).number_format='$#,##0.00 "MXN"'
    _fit(stats)

    headers=["Folio","Caso","Estatus","Turno","Google Maps","Ingreso total","Gasto mensual","Disponible","Integrantes","Ingreso per c\u00e1pita","Disponible per c\u00e1pita","Carga de gasto (%)","Cuota de referencia","Cuota final"];_header(cases,1,headers)
    for r,(s,p,d,c) in enumerate(records,2):
        vals=[s.folio,s.student_name,s.status,d.get("turno",""),"Abrir ubicaci\u00f3n",c.get("total_income",0),c.get("total_expenses",0),c.get("available",0),c.get("household_size",1),c.get("income_per_capita",0),c.get("available_per_capita",0),c.get("expense_burden_pct",0),c.get("reference_fee",0),c.get("final_fee")]
        for col,v in enumerate(vals,1):cases.cell(r,col,v)
        if p.get("maps_url"):cases.cell(r,5).hyperlink=p["maps_url"];cases.cell(r,5).style="Hyperlink"
        for col in (6,7,8,10,11,13,14):
            if cases.cell(r,col).value is not None:cases.cell(r,col).number_format='$#,##0.00 "MXN"'
    cases.freeze_panes="A2";_fit(cases)

    for idx,(s,p,d,c) in enumerate(records,1):
        ws=wb.create_sheet(("Caso_%s_%s"%(idx,_safe(s.student_name)))[:31]);ws["A1"]=f"{s.folio} - {s.student_name}";ws["A1"].font=Font(bold=True,size=14,color=GREEN);ws.merge_cells("A1:D1");_header(ws,3,["Campo","Valor"])
        rows=[("Turno",d.get("turno","")),("Ingreso total",c.get("total_income",0)),("Gasto mensual",c.get("total_expenses",0)),("Disponible",c.get("available",0)),("Integrantes",c.get("household_size",1)),("Cuota de referencia",c.get("reference_fee",0)),("Cuota final",c.get("final_fee")),("Google Maps","Abrir ubicaci\u00f3n"),("Contexto sociofamiliar",d.get("contexto_sociofamiliar",""))]
        rr=4
        for a,b in rows:
            ws.cell(rr,1,a);ws.cell(rr,2,b)
            if a=="Google Maps" and p.get("maps_url"):ws.cell(rr,2).hyperlink=p["maps_url"];ws.cell(rr,2).style="Hyperlink"
            rr+=1
        _fit(ws)
    out=BytesIO();wb.save(out);out.seek(0);return out
''')

write_ascii("app/routes/institutional_forms.py", r'''from __future__ import annotations
from datetime import datetime
from pathlib import Path
import shutil
from flask import Blueprint,current_app,flash,jsonify,redirect,render_template,request,send_file,url_for
from app.extensions import db
from app.models.study import Study
from app.services.institutional_form_service import delete_form,load_form,save_form
from app.services.institutional_export_service import build_bulk_excel,build_case_excel,build_case_word

institutional_bp=Blueprint("institutional",__name__,url_prefix="/estudios")

def _sync(study,p):
    d=p.get("data",{});c=p.get("calculation",{});parts=[d.get("nombre_alumno",""),d.get("apellido_paterno_alumno",""),d.get("apellido_materno_alumno","")];name=" ".join(str(x).strip() for x in parts if str(x or "").strip())
    if name:study.student_name=name
    if hasattr(study,"total_income"):study.total_income=float(c.get("total_income") or 0)
    if hasattr(study,"total_expenses"):study.total_expenses=float(c.get("total_expenses") or 0)
    if hasattr(study,"household_size"):study.household_size=int(c.get("household_size") or 1)
    if hasattr(study,"final_fee"):study.final_fee=c.get("final_fee")
    study.status="FORMULARIO";db.session.commit()

@institutional_bp.get("/")
def index():
    return render_template("institutional_cases.html",studies=Study.query.order_by(Study.id.desc()).all())

@institutional_bp.post("/nuevo")
def new_case():
    name=(request.form.get("student_name") or "").strip() or "Nuevo estudio";s=Study(folio="ES-"+datetime.now().strftime("%Y%m%d-%H%M%S"),student_name=name,status="FORMULARIO");db.session.add(s);db.session.commit();return redirect(url_for("institutional.form",study_id=s.id))

@institutional_bp.get("/<int:study_id>")
def form(study_id):
    s=Study.query.get_or_404(study_id);return render_template("institutional_form.html",study=s,payload=load_form(current_app.instance_path,study_id))

@institutional_bp.post("/<int:study_id>/guardar")
def save(study_id):
    s=Study.query.get_or_404(study_id);p=save_form(current_app.instance_path,study_id,request.get_json(silent=True) or {});_sync(s,p);return jsonify(ok=True,updated_at=p.get("updated_at"),calculation=p.get("calculation",{}),maps_url=p.get("maps_url",""),maps_static_url=p.get("maps_static_url",""))

@institutional_bp.get("/<int:study_id>/preview")
def preview(study_id):
    s=Study.query.get_or_404(study_id);return render_template("institutional_preview.html",study=s,payload=load_form(current_app.instance_path,study_id))

@institutional_bp.get("/<int:study_id>/excel")
def excel(study_id):
    s=Study.query.get_or_404(study_id);f=build_case_excel(s,current_app.instance_path);return send_file(f,as_attachment=True,download_name=f"{s.folio}_{s.student_name}_estudio.xlsx".replace(" ","_"),mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

@institutional_bp.get("/<int:study_id>/word")
def word(study_id):
    s=Study.query.get_or_404(study_id);f=build_case_word(s,current_app.instance_path);return send_file(f,as_attachment=True,download_name=f"{s.folio}_{s.student_name}_estudio.docx".replace(" ","_"),mimetype="application/vnd.openxmlformats-officedocument.wordprocessingml.document")

@institutional_bp.post("/exportar/excel")
def bulk_excel():
    ids=[]
    for v in request.form.getlist("study_ids"):
        try:ids.append(int(v))
        except:pass
    if not ids:flash("Seleccione al menos un caso.","warning");return redirect(url_for("institutional.index"))
    studies=Study.query.filter(Study.id.in_(ids)).order_by(Study.id.asc()).all();f=build_bulk_excel(studies,current_app.instance_path);return send_file(f,as_attachment=True,download_name="IPPLIAP_Estudios_"+datetime.now().strftime("%Y%m%d_%H%M")+".xlsx",mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

@institutional_bp.post("/<int:study_id>/eliminar")
def delete(study_id):
    s=Study.query.get_or_404(study_id);delete_form(current_app.instance_path,study_id)
    for p in (Path(current_app.instance_path)/"field_extractions"/f"study_{study_id}.json",Path(current_app.instance_path)/"analysis"/f"study_{study_id}.json"):
        if p.exists():p.unlink()
    db.session.delete(s);db.session.commit();flash("Caso eliminado.","success");return redirect(url_for("institutional.index"))
''')

write_utf8("app/templates/institutional_cases.html", '''{% extends "base.html" %}
{% block title %}Estudios socioecon&oacute;micos{% endblock %}{% block page_name %}Estudios socioecon&oacute;micos{% endblock %}
{% block content %}
<section class="page-title-card"><div><span class="eyebrow">GESTI&Oacute;N INSTITUCIONAL</span><h1>Estudios socioecon&oacute;micos</h1><p>Capture cada expediente manualmente, revise la cuota de referencia y genere Word o Excel.</p></div></section>
<section class="section" id="nuevo"><article class="review-card"><span class="eyebrow">NUEVO ESTUDIO</span><h2>Crear expediente</h2><form method="POST" action="{{ url_for('institutional.new_case') }}" class="manual-new-form"><label>Nombre o identificador inicial<input name="student_name" placeholder="Ej. Mateo R&iacute;os" required></label><button class="btn btn-primary" type="submit">Crear formulario</button></form></article></section>
<section class="section"><form method="POST" action="{{ url_for('institutional.bulk_excel') }}"><div class="section-heading"><div><span class="eyebrow">EXPEDIENTES</span><h2>Casos registrados</h2></div><button class="btn btn-primary" type="submit">Excel de seleccionados</button></div><div class="study-grid">
{% for study in studies %}<article class="study-card"><label class="select-case"><input type="checkbox" name="study_ids" value="{{ study.id }}"> Seleccionar</label><span class="folio">{{ study.folio }}</span><h3>{{ study.student_name }}</h3><p>{{ study.status }}</p><div class="study-actions"><a class="btn btn-primary" href="{{ url_for('institutional.form', study_id=study.id) }}">Abrir formulario</a><a class="btn" href="{{ url_for('institutional.preview', study_id=study.id) }}">Vista previa</a><a class="btn" href="{{ url_for('institutional.word', study_id=study.id) }}">Word</a><a class="btn" href="{{ url_for('institutional.excel', study_id=study.id) }}">Excel</a></div><form method="POST" action="{{ url_for('institutional.delete', study_id=study.id) }}" onsubmit="return confirm('¿Eliminar definitivamente este caso?');"><button class="btn btn-danger" type="submit">Eliminar</button></form></article>{% else %}<article class="review-card"><h3>No hay casos registrados</h3><p>Cree el primer estudio desde el formulario superior.</p></article>{% endfor %}
</div></form></section>
<style>.manual-new-form{display:grid;grid-template-columns:1fr auto;gap:12px;align-items:end}.manual-new-form label{display:flex;flex-direction:column;gap:7px;font-weight:700}.select-case{display:flex;gap:8px;align-items:center;margin-bottom:12px;font-weight:700}.btn-danger{border-color:#b42318;color:#b42318;background:#fff}.section-heading{display:flex;justify-content:space-between;gap:16px;align-items:end;margin-bottom:18px}@media(max-width:760px){.manual-new-form{grid-template-columns:1fr}.section-heading{align-items:stretch;flex-direction:column}}</style>
{% endblock %}''')

write_utf8("app/templates/institutional_form.html", '''{% extends "base.html" %}
{% block title %}Formulario socioecon&oacute;mico{% endblock %}{% block page_name %}Formulario socioecon&oacute;mico{% endblock %}
{% block content %}
<section class="page-title-card"><div><span class="eyebrow">EXPEDIENTE {{ study.folio }}</span><h1>Formulario de estudio socioecon&oacute;mico</h1><p>Capture manualmente la informaci&oacute;n. Los cambios se guardan autom&aacute;ticamente.</p></div><span class="pilot-chip" id="saveState"><span class="pilot-dot"></span> Listo</span></section>
<form id="studyForm" autocomplete="off">
{% macro input(name,label,type='text',step='') -%}<label>{{ label }}<input name="{{ name }}" type="{{ type }}"{% if step %} step="{{ step }}"{% endif %}></label>{%- endmacro %}
<section class="section"><article class="review-card"><span class="eyebrow">1 &middot; SOLICITUD Y ALUMNO</span><h2>Datos generales del alumno</h2><div class="form-grid"><label>Tipo de solicitud<select name="solicitud_tipo"><option></option><option>Nueva</option><option>Renovaci&oacute;n</option></select></label><label>Turno<select name="turno"><option></option><option>Matutino</option><option>Vespertino</option></select></label>{{ input('grado','Grado que solicita') }}{{ input('fecha','Fecha','date') }}{{ input('nombre_alumno','Nombre') }}{{ input('apellido_paterno_alumno','Apellido paterno') }}{{ input('apellido_materno_alumno','Apellido materno') }}{{ input('fecha_nacimiento','Fecha de nacimiento','date') }}{{ input('edad','Edad','number') }}{{ input('telefono','Tel&eacute;fono') }}{{ input('celular','Celular') }}</div><h3>Domicilio</h3><div class="form-grid">{{ input('calle','Calle') }}{{ input('numero','N&uacute;mero') }}{{ input('colonia','Colonia') }}{{ input('codigo_postal','C&oacute;digo postal') }}{{ input('estado','Estado') }}</div></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">2 &middot; SOLICITANTE</span><h2>Datos de quien solicita la beca</h2><div class="form-grid">{{ input('solicitante_nombre','Nombre completo') }}{{ input('solicitante_parentesco','Parentesco con el alumno') }}{{ input('solicitante_edad','Edad','number') }}{{ input('solicitante_domicilio','Domicilio') }}{{ input('solicitante_telefono','Tel&eacute;fono') }}{{ input('solicitante_celular','Celular') }}{{ input('solicitante_escolaridad','Escolaridad') }}{{ input('solicitante_ocupacion','Ocupaci&oacute;n') }}{{ input('solicitante_trabajo','Nombre y domicilio del trabajo') }}{{ input('solicitante_trabajo_telefono','Tel&eacute;fono del trabajo') }}{{ input('solicitante_correo','Correo electr&oacute;nico','email') }}</div><label class="full-label">Raz&oacute;n por la cual solicita ayuda financiera<textarea name="razon_apoyo" rows="4"></textarea></label></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">FAMILIA</span><h2>Integrantes de la familia</h2><div class="table-wrap"><table class="entry-table"><thead><tr><th>Nombre</th><th>Parentesco</th><th>Edad</th><th>Ocupaci&oacute;n</th><th></th></tr></thead><tbody id="familyRows"></tbody></table></div><button class="btn" type="button" id="addFamily">+ Agregar integrante</button><label style="max-width:280px;margin-top:12px">Integrantes considerados<input name="household_size" type="number" min="1" value="1"></label></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">3 &middot; VIVIENDA</span><h2>Condiciones de vivienda</h2><div class="form-grid"><label>Tenencia<select name="vivienda_tenencia"><option></option><option>Propia</option><option>Rentada</option><option>Prestada</option><option>Invadida</option></select></label><label>Tipo de vivienda<select name="vivienda_tipo"><option></option><option>Casa</option><option>Departamento</option><option>Cuarto</option><option>Vecindad</option></select></label>{{ input('habitaciones','Habitaciones','number') }}{{ input('dormitorios','Dormitorios','number') }}{{ input('espacios_vivienda','Sala, comedor, cocina y ba&ntilde;os') }}{{ input('paredes','Material de paredes') }}{{ input('techos','Material de techos') }}{{ input('pisos','Material de pisos') }}{{ input('servicios_vivienda','Servicios de la vivienda') }}{{ input('bienes_hogar','Bienes del hogar') }}{{ input('zona','Caracter&iacute;sticas de la zona') }}{{ input('comunidad','Servicios o espacios de la comunidad') }}{{ input('transporte','Transporte que utiliza') }}{{ input('transporte_modelo','Modelo') }}{{ input('transporte_anio','A&ntilde;o') }}</div><label class="full-label">Referencias<textarea name="referencias" rows="3"></textarea></label><div class="map-card"><div><span class="eyebrow">UBICACI&Oacute;N DE REFERENCIA</span><h3>Google Maps</h3><p>La ubicaci&oacute;n es aproximada y debe confirmarse con la familia; no comprueba por s&iacute; sola el domicilio.</p><a id="mapsLink" class="btn" target="_blank" rel="noopener">Abrir en Google Maps</a></div><img id="mapsPreview" alt="Mapa de referencia" hidden></div></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">4 &middot; SITUACI&Oacute;N ECON&Oacute;MICA</span><h2>Ingresos del hogar</h2><div class="table-wrap"><table class="entry-table wide"><thead><tr><th>Integrante</th><th>Lugar de trabajo</th><th>Antig&uuml;edad</th><th>Puesto</th><th>Ingreso mensual</th><th>Aportaci&oacute;n mensual</th><th></th></tr></thead><tbody id="incomeRows"></tbody></table></div><button class="btn" type="button" id="addIncome">+ Agregar ingreso</button><div class="form-grid" style="margin-top:14px">{{ input('total_ingresos','Total de ingresos mensual (opcional si se llenan aportaciones)','number','0.01') }}{{ input('beca_actual_pct','Beca actual (%)','number','0.01') }}</div></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">5 &middot; DISTRIBUCI&Oacute;N DEL GASTO</span><h2>Gastos familiares</h2><p class="muted">Predial, gastos anuales y vacaciones se convierten a equivalente mensual dividiendo entre 12.</p><div class="form-grid money-grid">{{ input('predial_anual','Impuesto predial anual (MXN)','number','0.01') }}{{ input('gastos_anuales','Otros gastos anuales (MXN)','number','0.01') }}{{ input('vacaciones_anual','Vacaciones anual (MXN)','number','0.01') }}{{ input('renta','Renta mensual (MXN)','number','0.01') }}{{ input('luz','Luz mensual (MXN)','number','0.01') }}{{ input('agua','Agua mensual (MXN)','number','0.01') }}{{ input('telefono_gasto','Tel&eacute;fono mensual (MXN)','number','0.01') }}{{ input('gas','Gas mensual (MXN)','number','0.01') }}{{ input('alimentos','Alimentos mensual (MXN)','number','0.01') }}{{ input('automovil','Autom&oacute;vil mensual (MXN)','number','0.01') }}{{ input('pasajes','Pasajes mensual (MXN)','number','0.01') }}{{ input('colegiaturas','Colegiaturas mensual (MXN)','number','0.01') }}{{ input('vestido','Vestido mensual (MXN)','number','0.01') }}{{ input('medico_medicinas','M&eacute;dico y medicinas mensual (MXN)','number','0.01') }}{{ input('muebles_hogar','Muebles del hogar mensual (MXN)','number','0.01') }}{{ input('creditos_personales','Cr&eacute;ditos personales mensual (MXN)','number','0.01') }}{{ input('otros_gastos','Otros gastos mensual (MXN)','number','0.01') }}</div></article></section>
<section class="section"><article class="review-card"><span class="eyebrow">SALUD Y CONTEXTO</span><h2>Informaci&oacute;n cualitativa</h2><div class="form-grid">{{ input('servicio_medico','Servicio m&eacute;dico') }}{{ input('enfermedades_cronicas','Enfermedades cr&oacute;nicas en la familia') }}{{ input('tiempo_libre','Tiempo libre') }}{{ input('final_fee','Cuota final autorizada (MXN)','number','0.01') }}</div><label class="full-label">Observaciones<textarea name="observaciones" rows="4"></textarea></label><label class="full-label">Contexto sociofamiliar<textarea name="contexto_sociofamiliar" rows="5" placeholder="Separaci&oacute;n de padres, aportaciones parciales, apoyo de abuelos, ingresos irregulares, becas u otras circunstancias relevantes."></textarea></label></article></section>
</form>
<section class="section"><article class="review-card preview-panel"><div><span class="eyebrow">C&Aacute;LCULO</span><h2>Vista previa de la cuota</h2><p id="explanation">Capture ingresos y gastos para obtener la referencia.</p></div><div class="metric-grid"><div><small>Ingreso</small><strong id="mIncome">$0.00 MXN</strong></div><div><small>Gasto mensual</small><strong id="mExpense">$0.00 MXN</strong></div><div><small>Disponible</small><strong id="mAvailable">$0.00 MXN</strong></div><div><small>Carga de gasto</small><strong id="mBurden">0.00%</strong></div><div class="reference"><small>Cuota de referencia</small><strong id="mReference">$0.00 MXN</strong></div></div><div class="bottom-actions"><button class="btn btn-primary" type="button" id="generatePreview">Guardar y calcular</button><a class="btn" href="{{ url_for('institutional.preview', study_id=study.id) }}">Vista previa completa</a><a class="btn" href="{{ url_for('institutional.word', study_id=study.id) }}">Word</a><a class="btn" href="{{ url_for('institutional.excel', study_id=study.id) }}">Excel</a></div></article></section>
<style>.form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}.form-grid label,.full-label{display:flex;flex-direction:column;gap:7px;font-weight:700}.full-label{margin-top:14px}.table-wrap{overflow:auto}.entry-table{width:100%;border-collapse:collapse;margin:10px 0}.entry-table th,.entry-table td{border:1px solid #d8dfd2;padding:7px}.entry-table input{min-width:110px}.wide{min-width:900px}.map-card{margin-top:18px;border:1px solid #d8dfd2;border-radius:16px;padding:16px;display:grid;grid-template-columns:1fr 360px;gap:20px;align-items:center}.map-card img{width:100%;border-radius:12px}.metric-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:18px 0}.metric-grid>div{padding:14px;border:1px solid #d8dfd2;border-radius:12px;display:flex;flex-direction:column;gap:5px}.metric-grid .reference{background:#edf6df;border-color:#77a836}.muted{opacity:.75}@media(max-width:900px){.form-grid,.metric-grid,.map-card{grid-template-columns:1fr}.money-grid{grid-template-columns:1fr 1fr}}@media(max-width:600px){.money-grid{grid-template-columns:1fr}}</style>
<script>
const initial={{ payload|tojson }},form=document.getElementById('studyForm'),state=document.getElementById('saveState'),familyBody=document.getElementById('familyRows'),incomeBody=document.getElementById('incomeRows');let timer=null,saving=false;
function esc(v){return String(v??'').replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;')}
function addFamily(r={}){const tr=document.createElement('tr');tr.innerHTML=`<td><input data-k="nombre" value="${esc(r.nombre)}"></td><td><input data-k="parentesco" value="${esc(r.parentesco)}"></td><td><input data-k="edad" type="number" value="${esc(r.edad)}"></td><td><input data-k="ocupacion" value="${esc(r.ocupacion)}"></td><td><button type="button" class="btn remove-row">&times;</button></td>`;familyBody.appendChild(tr)}
function addIncome(r={}){const tr=document.createElement('tr');tr.innerHTML=`<td><input data-k="integrante" value="${esc(r.integrante)}"></td><td><input data-k="lugar_trabajo" value="${esc(r.lugar_trabajo)}"></td><td><input data-k="antiguedad" value="${esc(r.antiguedad)}"></td><td><input data-k="puesto" value="${esc(r.puesto)}"></td><td><input data-k="ingreso_mensual" type="number" step="0.01" value="${esc(r.ingreso_mensual)}"></td><td><input data-k="aportacion_mensual" type="number" step="0.01" value="${esc(r.aportacion_mensual)}"></td><td><button type="button" class="btn remove-row">&times;</button></td>`;incomeBody.appendChild(tr)}
function rows(body){return [...body.querySelectorAll('tr')].map(tr=>{const o={};tr.querySelectorAll('[data-k]').forEach(el=>o[el.dataset.k]=el.value.trim());return o}).filter(o=>Object.values(o).some(Boolean))}
function collect(){const data={};new FormData(form).forEach((v,k)=>data[k]=v);return {data,family_members:rows(familyBody),income_rows:rows(incomeBody)}}
function money(v){return new Intl.NumberFormat('es-MX',{style:'currency',currency:'MXN'}).format(Number(v||0))+' MXN'}
function render(c={},maps='',staticUrl=''){document.getElementById('mIncome').textContent=money(c.total_income);document.getElementById('mExpense').textContent=money(c.total_expenses);document.getElementById('mAvailable').textContent=money(c.available);document.getElementById('mBurden').textContent=Number(c.expense_burden_pct||0).toFixed(2)+'%';document.getElementById('mReference').textContent=money(c.reference_fee);document.getElementById('explanation').textContent=c.explanation||'';const l=document.getElementById('mapsLink');if(maps){l.href=maps;l.style.opacity='1';l.style.pointerEvents='auto'}else{l.removeAttribute('href');l.style.opacity='.45';l.style.pointerEvents='none'}const img=document.getElementById('mapsPreview');if(staticUrl){img.src=staticUrl;img.hidden=false}else{img.hidden=true;img.removeAttribute('src')}}
async function save(){if(saving)return null;saving=true;state.textContent='Guardando...';try{const r=await fetch('{{ url_for("institutional.save",study_id=study.id) }}',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(collect())});const j=await r.json();if(!r.ok||!j.ok)throw 0;state.textContent='Guardado';render(j.calculation,j.maps_url,j.maps_static_url);return j}catch(e){state.textContent='Error al guardar';return null}finally{saving=false}}
function schedule(){clearTimeout(timer);state.textContent='Cambios pendientes';timer=setTimeout(save,900)}
const d=initial.data||{};for(const el of form.elements){if(el.name&&d[el.name]!==undefined&&d[el.name]!==null)el.value=d[el.name]}(initial.family_members||[]).forEach(addFamily);if(!familyBody.children.length)addFamily();(initial.income_rows||[]).forEach(addIncome);if(!incomeBody.children.length)addIncome();render(initial.calculation||{},initial.maps_url||'',initial.maps_static_url||'');
form.addEventListener('input',schedule);form.addEventListener('change',schedule);document.getElementById('addFamily').onclick=()=>{addFamily();schedule()};document.getElementById('addIncome').onclick=()=>{addIncome();schedule()};document.addEventListener('click',e=>{if(e.target.classList.contains('remove-row')){e.target.closest('tr').remove();schedule()}});document.getElementById('generatePreview').onclick=async()=>{const j=await save();if(j)document.querySelector('.preview-panel').scrollIntoView({behavior:'smooth',block:'center'})};
</script>
{% endblock %}''')

write_utf8("app/templates/institutional_preview.html", '''{% extends "base.html" %}
{% block title %}Vista previa del estudio{% endblock %}{% block page_name %}Vista previa del estudio{% endblock %}
{% block content %}{% set d=payload.get('data',{}) %}{% set c=payload.get('calculation',{}) %}
<section class="page-title-card"><div><span class="eyebrow">{{ study.folio }}</span><h1>{{ study.student_name }}</h1><p>Resumen previo para revisi&oacute;n institucional.</p></div><a class="btn" href="{{ url_for('institutional.form',study_id=study.id) }}">Editar formulario</a></section>
<section class="section"><div class="metric-grid"><div><small>Ingreso total</small><strong>$ {{ '%.2f'|format(c.get('total_income',0)) }} MXN</strong></div><div><small>Gasto mensual</small><strong>$ {{ '%.2f'|format(c.get('total_expenses',0)) }} MXN</strong></div><div><small>Disponible</small><strong>$ {{ '%.2f'|format(c.get('available',0)) }} MXN</strong></div><div><small>Carga de gasto</small><strong>{{ '%.2f'|format(c.get('expense_burden_pct',0)) }}%</strong></div><div class="reference"><small>Cuota de referencia</small><strong>$ {{ '%.2f'|format(c.get('reference_fee',0)) }} MXN</strong></div></div></section>
<section class="section"><article class="review-card"><span class="eyebrow">FUNDAMENTO</span><h2>Lectura del c&aacute;lculo</h2><p>{{ c.get('explanation','') }}</p><p><strong>Cuota final autorizada:</strong> {% if c.get('final_fee') is not none %}$ {{ '%.2f'|format(c.get('final_fee')) }} MXN{% else %}Pendiente{% endif %}</p></article></section>
{% if payload.get('maps_url') %}<section class="section"><article class="review-card"><span class="eyebrow">UBICACI&Oacute;N</span><h2>Referencia de Google Maps</h2><p>Esta referencia no confirma que el punto corresponda exactamente a la vivienda.</p><a class="btn" target="_blank" rel="noopener" href="{{ payload.get('maps_url') }}">Abrir en Google Maps</a>{% if payload.get('maps_static_url') %}<img src="{{ payload.get('maps_static_url') }}" alt="Mapa de referencia" style="display:block;max-width:640px;width:100%;margin-top:16px;border-radius:14px">{% endif %}</article></section>{% endif %}
<section class="section"><article class="review-card"><div class="bottom-actions"><a class="btn btn-primary" href="{{ url_for('institutional.word',study_id=study.id) }}">Descargar Word</a><a class="btn btn-primary" href="{{ url_for('institutional.excel',study_id=study.id) }}">Descargar Excel</a><a class="btn" href="{{ url_for('institutional.index') }}">Volver a casos</a></div></article></section>
<style>.metric-grid{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.metric-grid>div{padding:16px;border:1px solid #d8dfd2;border-radius:14px;display:flex;flex-direction:column;gap:6px}.reference{background:#edf6df;border-color:#77a836}@media(max-width:900px){.metric-grid{grid-template-columns:1fr 1fr}}@media(max-width:520px){.metric-grid{grid-template-columns:1fr}}</style>
{% endblock %}''')

write_utf8("app/templates/index.html", '''{% extends "base.html" %}
{% block title %}Estudios socioecon&oacute;micos{% endblock %}{% block page_name %}Estudios socioecon&oacute;micos{% endblock %}
{% block content %}<section class="page-title-card"><div><span class="eyebrow">IPPLIAP</span><h1>Formulario de estudios socioecon&oacute;micos</h1><p>Capture manualmente cada caso, obtenga una cuota de referencia y genere los documentos institucionales.</p></div><a class="btn btn-primary" href="{{ url_for('institutional.index') }}">Abrir casos</a></section><section class="section"><article class="review-card"><h2>Flujo de trabajo</h2><div class="flow-cards"><div><strong>1. Capturar</strong><span>Formulario por alumno</span></div><div><strong>2. Calcular</strong><span>Ingresos, gastos e indicadores</span></div><div><strong>3. Revisar</strong><span>Cuota de referencia</span></div><div><strong>4. Autorizar</strong><span>Decisi&oacute;n institucional</span></div><div><strong>5. Exportar</strong><span>Word y Excel</span></div></div></article></section><style>.flow-cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px}.flow-cards>div{padding:18px;border:1px solid #d8dfd2;border-radius:14px;display:flex;flex-direction:column;gap:5px}@media(max-width:900px){.flow-cards{grid-template-columns:1fr 1fr}}@media(max-width:520px){.flow-cards{grid-template-columns:1fr}}</style>{% endblock %}''')

init=root/"app/__init__.py";t=init.read_text(encoding="utf-8-sig")
if "app.register_blueprint(institutional_bp)" not in t:
    ms=list(re.finditer(r"(?m)^([ \t]*)return[ \t]+app[ \t]*$",t))
    if not ms:raise SystemExit("No se encontro return app")
    m=ms[-1];ind=m.group(1);ins=ind+"from app.routes.institutional_forms import institutional_bp\n"+ind+"app.register_blueprint(institutional_bp)\n\n";t=t[:m.start()]+ins+t[m.start():];init.write_text(t,encoding="utf-8",newline="\n")

base=root/"app/templates/base.html"
if base.exists():
    b=base.read_text(encoding="utf-8-sig")
    aside='''<aside class="sidebar"><div class="side-info"><div class="brand"><picture class="brand-mark"><source srcset="{{ url_for('static', filename='img/ippliap-mark.svg') }}" type="image/svg+xml"><img src="{{ url_for('static', filename='img/ippliap-mark.png') }}" alt="IPPLIAP" class="brand-logo" width="48" height="48"></picture><div><strong>IPPLIAP</strong><small>Estudios socioecon&oacute;micos</small></div></div><span class="eyebrow">GESTI&Oacute;N INSTITUCIONAL</span><nav class="side-nav"><a href="{{ url_for('main.index') }}">Inicio</a><a href="{{ url_for('institutional.index') }}#nuevo">Nuevo estudio</a><a href="{{ url_for('institutional.index') }}">Casos</a><a href="{{ url_for('institutional.index') }}">Reportes</a></nav><div class="support-note"><strong>Apoyo humano</strong><span>La cuota de referencia no sustituye la valoraci&oacute;n institucional.</span></div></div></aside>'''
    b2,n=re.subn(r'<aside class="sidebar">.*?</aside>',aside,b,count=1,flags=re.S)
    if n==0:raise SystemExit("No se localizo sidebar")
    for old,new in [("Prototipo B","Estudios socioecon\u00f3micos"),("PILOTO EXPERIMENTAL","GESTI\u00d3N INSTITUCIONAL"),("Piloto activo","Sistema activo"),("Captura \u00b7 OpenCV \u00b7 OCR \u00b7 Revisi\u00f3n \u00b7 Reportes","Formularios \u00b7 C\u00e1lculos \u00b7 Word \u00b7 Excel")]:b2=b2.replace(old,new)
    base.write_text(b2,encoding="utf-8",newline="\n")

env=root/".env.example";e=env.read_text(encoding="utf-8-sig") if env.exists() else ""
for line in ["# Formulario institucional","MAX_REFERENCE_FEE=4500","FEE_INCOME_RATIO=0.08","FEE_DISPOSABLE_RATIO=0.20","# Opcional: Maps Static API","GOOGLE_MAPS_API_KEY="]:
    key=line.split("=",1)[0]
    if "=" in line and any(x.startswith(key+"=") for x in e.splitlines()):continue
    if line not in e:e+=("\n" if e and not e.endswith("\n") else "")+line
env.write_text(e+("\n" if not e.endswith("\n") else ""),encoding="utf-8",newline="\n")

gi=root/".gitignore";g=gi.read_text(encoding="utf-8-sig") if gi.exists() else ""
for x in [".env","instance/","exports/","uploads/"]:
    if x not in g.splitlines():g+=("\n" if g and not g.endswith("\n") else "")+x
gi.write_text(g+("\n" if not g.endswith("\n") else ""),encoding="utf-8",newline="\n")
print("PARCHE_INSTITUCIONAL_OK")
'@

$Tmp = Join-Path $env:TEMP "ippliap_ps25_patch.py"
$Patch | Set-Content -Encoding ASCII $Tmp
python $Tmp
if ($LASTEXITCODE -ne 0) { throw "Fallo el parche PS25." }
Remove-Item $Tmp -Force -ErrorAction SilentlyContinue

python -m compileall app -q
if ($LASTEXITCODE -ne 0) { throw "Fallo compileall." }

python -c "from app import create_app; a=create_app(); print([str(r) for r in a.url_map.iter_rules() if '/estudios' in str(r)])"
if ($LASTEXITCODE -ne 0) { throw "Fallo create_app." }

Write-Host "========================================================" -ForegroundColor Green
Write-Host " PS25 COMPLETADO CORRECTAMENTE" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host "Siguiente: .\26_validar_formulario_institucional.ps1" -ForegroundColor Cyan

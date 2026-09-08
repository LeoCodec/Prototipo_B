from __future__ import annotations
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

    valid_family=[]
    for row in family_members:
        if not isinstance(row,dict):
            continue
        if any(str(row.get(k) or "").strip() for k in ("nombre","parentesco","edad","ocupacion")):
            valid_family.append(row)

    explicit_size=0
    try:
        explicit_size=int(float(data.get("household_size") or 0))
    except:
        explicit_size=0

    # Si existen integrantes capturados, ellos son la fuente principal.
    # Esto evita conservar un valor antiguo (por ejemplo 2) cuando en la tabla hay 3 personas.
    n=len(valid_family) if valid_family else explicit_size
    n=max(n,1)
    data["household_size"]=n

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
    if income<=0:
        explanation="No se calcula una cuota de referencia porque no hay ingreso mensual confirmado."
    elif available<=0:
        explanation="La disponibilidad mensual es igual o menor que cero; la cuota de referencia es $0.00 MXN."
    else:
        explanation="La cuota de referencia toma el menor límite entre el tope configurado, un porcentaje del ingreso y un porcentaje de la disponibilidad. Es orientativa y no sustituye la valoración institucional."
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

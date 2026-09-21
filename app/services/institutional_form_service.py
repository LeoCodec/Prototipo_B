from __future__ import annotations
import json, os
from datetime import datetime
from pathlib import Path
from urllib.parse import quote_plus

ANNUAL_EXPENSE_FIELDS=("predial_anual","gastos_anuales","vacaciones_anual")
MONTHLY_EXPENSE_FIELDS=("renta","luz","agua","telefono_gasto","gas","alimentos","automovil","pasajes","colegiaturas","vestido","medico_medicinas","muebles_hogar","creditos_personales","otros_gastos")

def _file(instance_path,study_id):
    p=Path(instance_path)/"institutional_forms"
    p.mkdir(parents=True,exist_ok=True)
    return p/f"study_{study_id}.json"

def _number(value,default=0.0):
    if value is None:return default
    t=str(value).strip()
    if not t:return default
    t=t.replace("$","").replace("MXN","").replace(" ","")
    if "," in t and "." in t:
        t=t.replace(",","") if t.rfind(".")>t.rfind(",") else t.replace(".","").replace(",",".")
    elif "," in t:
        parts=t.split(",")
        t="".join(parts[:-1])+"."+parts[-1] if len(parts[-1])==2 else t.replace(",","")
    try:return float(t)
    except:return default

def _truthy(v):
    if isinstance(v,bool):
        return v
    return str(v or "").strip().lower() in {"1","true","si","s?","on","yes"}

def load_form(instance_path,study_id):
    p=_file(instance_path,study_id)
    if not p.exists():
        return {
            "study_id":study_id,
            "data":{},
            "family_members":[],
            "income_rows":[],
            "extra_expenses":[],
            "calculation":{},
            "updated_at":None
        }
    try:
        d=json.loads(p.read_text(encoding="utf-8"))
    except:
        d={}
    d.setdefault("study_id",study_id)
    d.setdefault("data",{})
    d.setdefault("family_members",[])
    d.setdefault("income_rows",[])
    d.setdefault("extra_expenses",[])
    d.setdefault("calculation",{})
    d.setdefault("updated_at",None)
    return d

def _income_total(data,rows):
    explicit=_number(data.get("total_ingresos"),None)
    if explicit is not None:
        return max(explicit,0.0)

    total=0.0
    for r in rows:
        v=_number(r.get("aportacion_mensual"),None)
        if v is None:
            v=_number(r.get("ingreso_mensual"),0.0)
        total+=max(v or 0.0,0.0)
    return total

def _expenses_monthly(data,extra_expenses=None):
    total=0.0
    detail={}
    extras=[]

    for k in MONTHLY_EXPENSE_FIELDS:
        v=max(_number(data.get(k),0.0),0.0)
        detail[k]=v
        total+=v

    for k in ANNUAL_EXPENSE_FIELDS:
        anual=max(_number(data.get(k),0.0),0.0)
        mensual=anual/12.0
        detail[k]=anual
        detail[k+"_mensual_equiv"]=mensual
        total+=mensual

    for row in extra_expenses or []:
        if not isinstance(row,dict):
            continue

        concepto=str(row.get("concepto") or "").strip()
        monto=max(_number(row.get("monto_mensual"),0.0),0.0)
        detalle=str(row.get("detalle") or "").strip()

        if not concepto and monto<=0 and not detalle:
            continue

        extras.append({
            "concepto":concepto or "Gasto adicional",
            "monto_mensual":round(monto,2),
            "detalle":detalle
        })
        total+=monto

    return total,detail,extras

def _context_flags(data,calc,extras):
    flags=[]

    income=float(calc.get("total_income") or 0)
    available=float(calc.get("available") or 0)
    burden=float(calc.get("expense_burden_pct") or 0)

    if income>0 and available<=0:
        flags.append(
            "Los gastos registrados igualan o superan el ingreso mensual; "
            "conviene revisar este punto durante la valoraci?n."
        )
    elif income>0 and burden>=80:
        flags.append(
            "La carga de gasto registrada es elevada respecto del ingreso mensual."
        )

    texto=" ".join(
        str(data.get(k) or "")
        for k in (
            "servicio_medico",
            "enfermedades_cronicas",
            "observaciones",
            "contexto_sociofamiliar",
            "razon_apoyo"
        )
    ).lower()

    texto+=" "+" ".join(
        (
            str(x.get("concepto") or "")+" "+
            str(x.get("detalle") or "")
        ).lower()
        for x in extras
        if isinstance(x,dict)
    )

    salud=(
        "implante","medic","terapia","tratamiento","hospital",
        "cirug","pr?tesis","protesis","aparato audit","auxiliar audit"
    )

    if any(x in texto for x in salud):
        flags.append(
            "Se registran condiciones o gastos relacionados con salud que "
            "conviene revisar junto con el contexto y, cuando corresponda, sus comprobantes."
        )

    apoyo=(
        "abuelo","abuela","apoyo","aporta",
        "aportaci?n parcial","aportacion parcial",
        "separad","madre soltera","padre soltero","tutor"
    )

    if any(x in texto for x in apoyo):
        flags.append(
            "Se registran apoyos familiares o una estructura particular de cuidado "
            "que debe considerarse dentro de la valoraci?n social."
        )

    return flags

def calculate_reference(data,family_members=None,income_rows=None,extra_expenses=None):
    family_members=family_members or []
    income_rows=income_rows or []
    extra_expenses=extra_expenses or []

    income=_income_total(data,income_rows)
    expenses,detail,extras=_expenses_monthly(data,extra_expenses)
    available=income-expenses

    valid_family=[]
    responsible=[]

    for row in family_members:
        if not isinstance(row,dict):
            continue

        if any(
            str(row.get(k) or "").strip()
            for k in ("nombre","parentesco","edad","ocupacion")
        ):
            clean=dict(row)
            clean["responsable"]=_truthy(row.get("responsable"))
            valid_family.append(clean)

            if clean["responsable"]:
                nombre=str(clean.get("nombre") or "").strip()
                if nombre:
                    responsible.append(nombre)

    try:
        explicit_size=int(float(data.get("household_size") or 0))
    except:
        explicit_size=0

    n=len(valid_family) if valid_family else explicit_size
    n=max(n,1)
    data["household_size"]=n

    ipc=income/n
    dpc=available/n
    burden=(expenses/income*100.0) if income>0 else 0.0

    max_fee=max(_number(os.getenv("MAX_REFERENCE_FEE","4500"),4500.0),0.0)
    income_ratio=max(_number(os.getenv("FEE_INCOME_RATIO","0.08"),0.08),0.0)
    disposable_ratio=max(_number(os.getenv("FEE_DISPOSABLE_RATIO","0.20"),0.20),0.0)

    scholarship=min(
        max(_number(data.get("beca_actual_pct"),0.0),0.0),
        100.0
    )

    scholarship_cap=max_fee*(1.0-scholarship/100.0)

    raw=(
        0.0
        if income<=0 or available<=0
        else min(
            max_fee,
            scholarship_cap,
            income*income_ratio,
            available*disposable_ratio
        )
    )

    ref=round(raw/50.0)*50.0 if raw>0 else 0.0
    ref=min(max(ref,0.0),scholarship_cap,max_fee)

    final=_number(data.get("final_fee"),None)

    if income<=0:
        explanation=(
            "No se calcula una cuota de referencia porque no hay "
            "ingreso mensual confirmado."
        )
    elif available<=0:
        explanation=(
            "La disponibilidad mensual es igual o menor que cero; "
            "la cuota de referencia es $0.00 MXN."
        )
    else:
        explanation=(
            "La cuota de referencia toma el menor l?mite entre el tope configurado, "
            "un porcentaje del ingreso y un porcentaje de la disponibilidad. "
            "Es orientativa y no sustituye la valoraci?n institucional."
        )

    calc={
        "total_income":round(income,2),
        "total_expenses":round(expenses,2),
        "available":round(available,2),
        "household_size":n,
        "income_per_capita":round(ipc,2),
        "available_per_capita":round(dpc,2),
        "expense_burden_pct":round(burden,2),
        "reference_fee":round(ref,2),
        "final_fee":None if final is None else round(final,2),
        "max_reference_fee":round(max_fee,2),
        "income_ratio":income_ratio,
        "disposable_ratio":disposable_ratio,
        "scholarship_pct":scholarship,
        "scholarship_cap":round(scholarship_cap,2),
        "expense_detail":detail,
        "extra_expenses":extras,
        "responsible_members":responsible,
        "responsible_count":len(responsible),
        "explanation":explanation
    }

    calc["context_flags"]=_context_flags(data,calc,extras)

    return calc

def full_address(data):
    direct=str(data.get("domicilio") or "").strip()
    if direct:
        return direct

    parts=[
        data.get("calle"),
        data.get("numero"),
        data.get("colonia"),
        data.get("codigo_postal"),
        data.get("estado")
    ]

    return ", ".join(
        str(x).strip()
        for x in parts
        if str(x or "").strip()
    )

def _maps_query(data):
    return (
        str(data.get("maps_query") or "").strip()
        or full_address(data)
    )

def maps_search_url(data):
    manual=str(data.get("maps_url_manual") or "").strip()

    if manual.startswith("http://") or manual.startswith("https://"):
        return manual

    address=_maps_query(data)

    return (
        ""
        if not address
        else "https://www.google.com/maps/search/?api=1&query="+quote_plus(address)
    )

def maps_static_url(data):
    key=str(os.getenv("GOOGLE_MAPS_API_KEY") or "").strip()
    address=_maps_query(data)

    if not key or not address:
        return ""

    return (
        "https://maps.googleapis.com/maps/api/staticmap?center="
        +quote_plus(address)
        +"&zoom=18&size=640x360&maptype=roadmap&markers=color:red%7C"
        +quote_plus(address)
        +"&key="
        +quote_plus(key)
    )

def save_form(instance_path,study_id,body):
    data=dict(body.get("data") or {})
    family=list(body.get("family_members") or [])
    rows=list(body.get("income_rows") or [])
    extras=list(body.get("extra_expenses") or [])

    if not str(data.get("domicilio") or "").strip():
        data["domicilio"]=full_address(data)

    calc=calculate_reference(
        data,
        family,
        rows,
        extras
    )

    payload={
        "study_id":study_id,
        "data":data,
        "family_members":family,
        "income_rows":rows,
        "extra_expenses":extras,
        "calculation":calc,
        "maps_url":maps_search_url(data),
        "maps_static_url":maps_static_url(data),
        "updated_at":datetime.now().isoformat(timespec="seconds")
    }

    _file(instance_path,study_id).write_text(
        json.dumps(
            payload,
            ensure_ascii=False,
            indent=2
        ),
        encoding="utf-8"
    )

    return payload

def delete_form(instance_path,study_id):
    p=_file(instance_path,study_id)
    if p.exists():
        p.unlink()

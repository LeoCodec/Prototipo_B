from __future__ import annotations
import re, unicodedata
from difflib import SequenceMatcher
from decimal import Decimal, InvalidOperation

FIELDS = {
 "grado_solicita": ("Grado que solicita", ["GRADO QUE SOLICITA","GRADO SOLICITADO"], "text"),
 "fecha_entrevista": ("Fecha de entrevista", ["FECHA DE ENTREVISTA","FECHA ENTREVISTA"], "text"),
 "nombre_alumno": ("Nombre del alumno", ["NOMBRE DEL NIÃ‘O","NOMBRE DEL NINO","NOMBRE DEL ALUMNO","NOMBRE DE LA NIÃ‘A","NOMBRE DE LA NINA"], "text"),
 "edad": ("Edad", ["EDAD"], "integer"),
 "fecha_nacimiento": ("Fecha de nacimiento", ["FECHA DE NACIMIENTO"], "text"),
 "domicilio": ("Domicilio", ["DOMICILIO"], "text"),
 "telefono": ("TelÃ©fono", ["TELEFONO","TELÃ‰FONO","TEL.","CELULAR"], "text"),
 "total_ingresos": ("Total de ingresos", ["TOTAL DE INGRESOS","TOTAL INGRESOS","INGRESO TOTAL"], "money"),
 "predial": ("Predial", ["IMPUESTO PREDIAL","PREDIAL"], "money"),
 "renta": ("Renta", ["RENTA"], "money"),
 "luz": ("Luz", ["LUZ"], "money"),
 "agua": ("Agua", ["AGUA"], "money"),
 "telefono_gasto": ("TelÃ©fono (gasto)", ["TELEFONO","TELÃ‰FONO"], "money"),
 "gas": ("Gas", ["GAS"], "money"),
 "alimentos": ("Alimentos", ["ALIMENTOS"], "money"),
 "automovil": ("AutomÃ³vil", ["AUTOMOVIL","AUTOMÃ“VIL"], "money"),
 "pasajes": ("Pasajes", ["PASAJES"], "money_or_none"),
 "colegiaturas": ("Colegiaturas", ["COLEGIATURAS"], "money_or_none"),
 "vestido": ("Vestido", ["VESTIDO"], "money_or_none"),
 "medico_medicinas": ("MÃ©dico y medicinas", ["MEDICO Y MEDICINAS","MÃ‰DICO Y MEDICINAS"], "money_or_none"),
 "muebles_hogar": ("Muebles del hogar", ["MUEBLES DEL HOGAR"], "money_or_none"),
 "creditos_personales": ("CrÃ©ditos personales", ["CREDITOS PERSONALES","CRÃ‰DITOS PERSONALES"], "money_or_none"),
 "otros_gastos": ("Otros gastos", ["OTROS GASTOS"], "money_or_none"),
 "servicio_medico": ("Servicio mÃ©dico", ["SERVICIO MEDICO","SERVICIO MÃ‰DICO"], "text"),
 "enfermedades_cronicas": ("Enfermedades crÃ³nicas", ["ENFERMEDADES CRONICAS EN LA FAMILIA","ENFERMEDADES CRÃ“NICAS EN LA FAMILIA"], "text"),
 "tiempo_libre": ("Tiempo libre", ["TIEMPO LIBRE"], "text"),
 "referencias": ("Referencias", ["REFERENCIAS"], "same_line"),
 "observaciones": ("Observaciones", ["OBSERVACIONES"], "observations"),
 "turno": ("Turno", ["TURNO"], "text"),
}

EXPENSE_CONTEXT = ["PREDIAL","RENTA","LUZ","AGUA","GAS","ALIMENTOS","AUTOMOVIL","AUTOMÃ“VIL","PASAJES","COLEGIATURAS","VESTIDO"]
CONTROLLED = {"ninguno":"Ninguno","ninguna":"Ninguna","no aplica":"No aplica","no":"No","si":"SÃ­","sÃ­":"SÃ­"}

def fold(s):
    return ''.join(c for c in unicodedata.normalize('NFD', s or '') if unicodedata.category(c) != 'Mn').lower()

def normalize_text(text):
    text=(text or '').replace('\r','\n')
    text=re.sub(r'[ \t]+',' ',text)
    return re.sub(r'\n{3,}','\n\n',text).strip()

def label_tail(line, alias):
    fl, fa = fold(line), fold(alias)
    pat = r'^\s*' + re.escape(fa).replace(r'\ ', r'\s+') + r'(?=\s*[:;=\-_.]|(?:\s|$))'
    m = re.search(pat, fl, re.I)
    if not m: return None
    return re.sub(r'^[\s:;=\-_.]+','', line[m.end():]).strip()

def controlled(value):
    v = re.sub(r'[^A-Za-zÃÃ‰ÃÃ“ÃšÃœÃ‘Ã¡Ã©Ã­Ã³ÃºÃ¼Ã± ]+',' ',value or '')
    v = re.sub(r'\s+',' ',fold(v)).strip()
    if not v: return None
    if v in CONTROLLED: return CONTROLLED[v]
    best = max(CONTROLLED, key=lambda k: SequenceMatcher(None,v,fold(k)).ratio())
    score = SequenceMatcher(None,v,fold(best)).ratio()
    return CONTROLLED[best] if score >= .72 else None

def money(value):
    c=controlled(value)
    if c in {"Ninguno","Ninguna","No aplica","No"}: return Decimal('0')
    m=re.search(r'[-+]?\d[\d\s,.]*', value or '')
    if not m: return None
    raw=m.group(0).replace(' ','')
    if ',' in raw and '.' in raw:
        raw = raw.replace(',','') if raw.rfind('.') > raw.rfind(',') else raw.replace('.','').replace(',','.')
    elif ',' in raw:
        p=raw.split(','); raw=''.join(p[:-1])+'.'+p[-1] if len(p[-1])==2 else raw.replace(',','')
    try: return Decimal(raw)
    except InvalidOperation: return None

def normalize_value(value, kind):
    value=(value or '').strip()
    if not value: return ''

    if kind=='money_or_none':
        c=controlled(value)
        if c in {"Ninguno","Ninguna","No aplica","No"}:
            return c
        n=money(value)
        if n is not None:
            return f'$ {n:,.2f} MXN'
        return c or value

    if kind=='money':
        n=money(value)
        if n is not None:
            return f'$ {n:,.2f} MXN'
        c=controlled(value)
        return c or value

    if kind=='integer':
        m=re.search(r'\b\d{1,3}\b', value)
        return m.group(0) if m else value

    c=controlled(value)
    return c if c and len(value.split()) <= 3 else value

def is_expense_context(lines, i):
    nearby=' '.join(fold(x) for x in lines[max(0,i-5):i])
    return any(fold(x) in nearby for x in EXPENSE_CONTEXT)

def extract_one(lines, aliases, kind, name):
    for i,line in enumerate(lines):
        for alias in sorted(aliases,key=len,reverse=True):
            tail=label_tail(line,alias)
            if tail is None: continue
            if name=='telefono' and is_expense_context(lines,i): continue
            if name=='telefono_gasto' and not is_expense_context(lines,i): continue
            if kind=='same_line': raw=tail
            elif tail: raw=tail
            elif i+1 < len(lines):
                candidate=lines[i+1].strip()
                if any(label_tail(candidate,a) is not None for _,als,_ in FIELDS.values() for a in als): raw=''
                else: raw=candidate
            else: raw=''
            return raw, normalize_value(raw,kind), .84 if tail else (.62 if raw else 0)
    return '','',0

def extract_observations(lines):
    blocks=[]
    for i,line in enumerate(lines):
        tail=label_tail(line,'OBSERVACIONES')
        if tail is None: continue
        vals=[tail] if tail else []
        for nxt in lines[i+1:i+3]:
            if any(label_tail(nxt,a) is not None for k,(_,als,_) in FIELDS.items() if k!='observaciones' for a in als): break
            if nxt.strip(): vals.append(nxt.strip())
        if vals: blocks.append(' '.join(vals))
    raw=' | '.join(blocks)
    return raw,raw,.58 if raw else 0

def extract_fields(text):
    lines=[x.strip() for x in normalize_text(text).splitlines() if x.strip()]
    out={}
    for name,(label,aliases,kind) in FIELDS.items():
        raw,det,conf = extract_observations(lines) if kind=='observations' else extract_one(lines,aliases,kind,name)
        out[name]={"label":label,"kind":kind,"raw_detected":raw,"detected":det,"confirmed":det,"confidence":conf}
    cp=re.search(r'\b(?:C\.?\s*P\.?|CP)\s*[:\-]?\s*(\d{5})\b', normalize_text(text), re.I)
    out['codigo_postal']={"label":"CÃ³digo postal","kind":"text","raw_detected":cp.group(1) if cp else '',"detected":cp.group(1) if cp else '',"confirmed":cp.group(1) if cp else '',"confidence":.9 if cp else 0}
    return out

def combine_ocr_text(images):
    chunks=[]
    for image in images:
        text=(getattr(image,'confirmed_text',None) or getattr(image,'ocr_text',None) or '').strip()
        if text: chunks.append(f"--- PAGINA {getattr(image,'page_number','?')} ---\n{text}")
    return '\n\n'.join(chunks)


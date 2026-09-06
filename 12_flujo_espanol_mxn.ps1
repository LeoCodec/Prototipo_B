param([string]$ProjectPath = "C:\Users\Leo\Documents\Prototipo_B")
$ErrorActionPreference = "Stop"
Set-Location $ProjectPath
$Py = Join-Path $ProjectPath "venv\Scripts\python.exe"
if (-not (Test-Path $Py)) { throw "No se encontro venv\Scripts\python.exe" }
if ((git branch --show-current).Trim() -ne "main") { throw "Ejecutar en main." }

Write-Host "=== IPPLIAP PS12 - FLUJO + ESPANOL + MXN ===" -ForegroundColor Green
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "backup_ps12_$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
foreach ($f in @("app\services\field_extraction.py","app\templates\fields_detected.html","app\templates\study_detail.html")) {
  if (Test-Path $f) { $d = Join-Path $backup $f; New-Item -ItemType Directory -Force (Split-Path $d -Parent) | Out-Null; Copy-Item $f $d -Force }
}

@'
from __future__ import annotations
import re, unicodedata
from difflib import SequenceMatcher
from decimal import Decimal, InvalidOperation

FIELDS = {
 "grado_solicita": ("Grado que solicita", ["GRADO QUE SOLICITA","GRADO SOLICITADO"], "text"),
 "fecha_entrevista": ("Fecha de entrevista", ["FECHA DE ENTREVISTA","FECHA ENTREVISTA"], "text"),
 "nombre_alumno": ("Nombre del alumno", ["NOMBRE DEL NIÑO","NOMBRE DEL NINO","NOMBRE DEL ALUMNO","NOMBRE DE LA NIÑA","NOMBRE DE LA NINA"], "text"),
 "edad": ("Edad", ["EDAD"], "integer"),
 "fecha_nacimiento": ("Fecha de nacimiento", ["FECHA DE NACIMIENTO"], "text"),
 "domicilio": ("Domicilio", ["DOMICILIO"], "text"),
 "telefono": ("Teléfono", ["TELEFONO","TELÉFONO","TEL.","CELULAR"], "text"),
 "total_ingresos": ("Total de ingresos", ["TOTAL DE INGRESOS","TOTAL INGRESOS","INGRESO TOTAL"], "money"),
 "predial": ("Predial", ["IMPUESTO PREDIAL","PREDIAL"], "money"),
 "renta": ("Renta", ["RENTA"], "money"),
 "luz": ("Luz", ["LUZ"], "money"),
 "agua": ("Agua", ["AGUA"], "money"),
 "telefono_gasto": ("Teléfono (gasto)", ["TELEFONO","TELÉFONO"], "money"),
 "gas": ("Gas", ["GAS"], "money"),
 "alimentos": ("Alimentos", ["ALIMENTOS"], "money"),
 "automovil": ("Automóvil", ["AUTOMOVIL","AUTOMÓVIL"], "money"),
 "pasajes": ("Pasajes", ["PASAJES"], "money_or_none"),
 "colegiaturas": ("Colegiaturas", ["COLEGIATURAS"], "money_or_none"),
 "vestido": ("Vestido", ["VESTIDO"], "money_or_none"),
 "medico_medicinas": ("Médico y medicinas", ["MEDICO Y MEDICINAS","MÉDICO Y MEDICINAS"], "money_or_none"),
 "muebles_hogar": ("Muebles del hogar", ["MUEBLES DEL HOGAR"], "money_or_none"),
 "creditos_personales": ("Créditos personales", ["CREDITOS PERSONALES","CRÉDITOS PERSONALES"], "money_or_none"),
 "otros_gastos": ("Otros gastos", ["OTROS GASTOS"], "money_or_none"),
 "servicio_medico": ("Servicio médico", ["SERVICIO MEDICO","SERVICIO MÉDICO"], "text"),
 "enfermedades_cronicas": ("Enfermedades crónicas", ["ENFERMEDADES CRONICAS EN LA FAMILIA","ENFERMEDADES CRÓNICAS EN LA FAMILIA"], "text"),
 "tiempo_libre": ("Tiempo libre", ["TIEMPO LIBRE"], "text"),
 "referencias": ("Referencias", ["REFERENCIAS"], "same_line"),
 "observaciones": ("Observaciones", ["OBSERVACIONES"], "observations"),
 "turno": ("Turno", ["TURNO"], "text"),
}

EXPENSE_CONTEXT = ["PREDIAL","RENTA","LUZ","AGUA","GAS","ALIMENTOS","AUTOMOVIL","AUTOMÓVIL","PASAJES","COLEGIATURAS","VESTIDO"]
CONTROLLED = {"ninguno":"Ninguno","ninguna":"Ninguna","no aplica":"No aplica","no":"No","si":"Sí","sí":"Sí"}

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
    v = re.sub(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]+',' ',value or '')
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
    if kind in {'money','money_or_none'}:
        n=money(value)
        if n is not None: return f'$ {n:,.2f} MXN'
        c=controlled(value)
        return c or value
    if kind=='integer':
        m=re.search(r'\b\d{1,3}\b', value); return m.group(0) if m else value
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
    out['codigo_postal']={"label":"Código postal","kind":"text","raw_detected":cp.group(1) if cp else '',"detected":cp.group(1) if cp else '',"confirmed":cp.group(1) if cp else '',"confidence":.9 if cp else 0}
    return out

def combine_ocr_text(images):
    chunks=[]
    for image in images:
        text=(getattr(image,'confirmed_text',None) or getattr(image,'ocr_text',None) or '').strip()
        if text: chunks.append(f"--- PAGINA {getattr(image,'page_number','?')} ---\n{text}")
    return '\n\n'.join(chunks)
'@ | Set-Content -Encoding UTF8 "app\services\field_extraction.py"

@'
{% extends "base.html" %}
{% block title %}Campos detectados{% endblock %}
{% block page_name %}Extracci&oacute;n por campos{% endblock %}
{% block content %}
<section class="page-title-card"><div><span class="eyebrow">DATOS PRELIMINARES &middot; MXN</span><h1>Campos detectados</h1><p>{{ study.folio }} &middot; {{ study.student_name }}</p></div><div class="bottom-actions"><form method="POST" action="{{ url_for('fields.reprocess', study_id=study.id) }}"><button class="btn" type="submit"><i class="bi bi-arrow-repeat"></i> Reprocesar OCR</button></form><form method="POST" action="{{ url_for('fields.run', study_id=study.id) }}"><button class="btn btn-primary" type="submit"><i class="bi bi-magic"></i> Extraer campos</button></form></div></section>
<div class="notice-card"><i class="bi bi-exclamation-triangle notice-icon"></i><div><strong>La extracci&oacute;n es preliminar.</strong><p>Importes en pesos mexicanos (MXN). La escritura manuscrita y los nombres propios deben confirmarse manualmente.</p></div></div>
<section class="section"><div class="review-card">{% if payload.fields %}<div class="review-stack">{% for name,item in payload.fields.items() %}<div style="display:grid;grid-template-columns:220px minmax(260px,1fr) 80px;gap:12px;align-items:center;margin-bottom:10px"><div><strong>{{ item.label or name.replace('_',' ')|title }}</strong>{% if item.raw_detected and item.raw_detected != item.detected %}<small style="display:block;opacity:.65">OCR: {{ item.raw_detected }}</small>{% endif %}</div><input value="{{ item.detected }}" readonly><small>{{ ((item.confidence or 0)*100)|round|int }}%</small></div>{% endfor %}</div><div class="bottom-actions"><a class="btn" href="{{ url_for('main.study_detail', study_id=study.id) }}">Volver al caso</a><a class="btn btn-primary" href="{{ url_for('review_fields.review', study_id=study.id) }}">Continuar a revisi&oacute;n</a></div>{% else %}<p>A&uacute;n no hay campos extra&iacute;dos. Pulse <strong>Reprocesar OCR</strong> y luego <strong>Extraer campos</strong>.</p>{% endif %}</div></section>
{% endblock %}
'@ | Set-Content -Encoding UTF8 "app\templates\fields_detected.html"

$patch = @'
from pathlib import Path
p=Path("app/templates/study_detail.html")
if p.exists():
    text=p.read_text(encoding="utf-8")
    marker="<!-- PS12-FLUJO -->"
    if marker not in text:
        card=r'''\n<!-- PS12-FLUJO -->\n<section class="section"><article class="review-card"><span class="eyebrow">FLUJO DEL EXPEDIENTE</span><h2>Continuar procesamiento</h2><div class="bottom-actions"><a class="btn btn-primary" href="{{ url_for('fields.detected', study_id=study.id) }}">Extracci&oacute;n por campos</a><a class="btn" href="{{ url_for('review_fields.review', study_id=study.id) }}">Revisi&oacute;n confirmada</a><a class="btn" href="{{ url_for('analysis.study', study_id=study.id) }}">Indicadores</a><a class="btn" href="{{ url_for('reports.excel_case', study_id=study.id) }}">Excel</a></div></article></section>\n'''
        pos=text.rfind("{% endblock %}")
        if pos!=-1:
            text=text[:pos]+card+text[pos:]
            p.write_text(text,encoding="utf-8")
'@
$tmp = Join-Path $env:TEMP "ps12_patch.py"; $patch | Set-Content -Encoding UTF8 $tmp; & $Py $tmp; Remove-Item $tmp -Force

& $Py -m compileall app -q
& $Py -c "from app import create_app; a=create_app(); print('OK create_app:',a.name)"
Write-Host "PS12 listo. Prueba /studies/1 y /fields/1" -ForegroundColor Green

from __future__ import annotations

import re
import unicodedata
from datetime import datetime

EXPENSE_ALIASES = {
    "predial_anual": ("impuesto predial", "predial"),
    "gastos_anuales": ("otros gastos anuales", "gastos anuales"),
    "vacaciones_anual": ("vacaciones",),
    "renta": ("renta",),
    "luz": ("luz", "electricidad"),
    "agua": ("agua",),
    "telefono_gasto": ("teléfono", "telefono", "internet"),
    "gas": ("gas",),
    "alimentos": ("alimentos", "comida", "despensa"),
    "automovil": ("automóvil", "automovil", "coche", "carro"),
    "pasajes": ("pasajes", "transporte"),
    "colegiaturas": ("colegiaturas", "colegiatura"),
    "vestido": ("vestido", "ropa"),
    "medico_medicinas": ("médico y medicinas", "medico y medicinas", "medicinas", "medicamentos"),
    "muebles_hogar": ("muebles del hogar", "muebles"),
    "creditos_personales": ("créditos personales", "creditos personales", "crédito personal", "credito personal"),
    "otros_gastos": ("otros gastos",),
}

DEFAULT_PERIOD = {
    "predial_anual": "anual",
    "gastos_anuales": "anual",
    "vacaciones_anual": "anual",
}

RELATIONS = {
    "madre": "Madre",
    "mamá": "Madre",
    "mama": "Madre",
    "padre": "Padre",
    "papá": "Padre",
    "papa": "Padre",
    "abuelo": "Abuelo",
    "abuela": "Abuela",
    "tío": "Tío",
    "tio": "Tío",
    "tía": "Tía",
    "tia": "Tía",
    "tutor": "Tutor",
    "tutora": "Tutora",
    "hermano": "Hermano",
    "hermana": "Hermana",
}

EXTRA_CONCEPTS = {
    "Implante": ("implante", "implantes"),
    "Terapia": ("terapia", "terapias"),
    "Tratamiento": ("tratamiento", "tratamientos"),
    "Aparato auditivo": ("aparato auditivo", "auxiliar auditivo"),
    "Prótesis": ("prótesis", "protesis"),
}


def _clean(value):
    return re.sub(r"\s+", " ", str(value or "")).strip()


def _fold(value):
    value = unicodedata.normalize("NFD", str(value or "").lower())
    return "".join(ch for ch in value if unicodedata.category(ch) != "Mn")


def _title(value):
    return " ".join(part.capitalize() for part in _clean(value).split())


def _money(value):
    value = _clean(value)
    match = re.search(r"\$?\s*(\d[\d\s.,]*)", value)
    if not match:
        return None
    raw = match.group(1).replace(" ", "")
    if "," in raw and "." in raw:
        raw = raw.replace(",", "") if raw.rfind(".") > raw.rfind(",") else raw.replace(".", "").replace(",", ".")
    elif "," in raw:
        parts = raw.split(",")
        raw = "".join(parts[:-1]) + "." + parts[-1] if len(parts[-1]) == 2 else raw.replace(",", "")
    try:
        return float(raw)
    except ValueError:
        return None


def _period(text, default="mensual"):
    folded = _fold(text)
    options = (
        ("cada cuatro meses", "cuatrimestral"),
        ("cada tres meses", "trimestral"),
        ("cada dos meses", "bimestral"),
        ("cada seis meses", "semestral"),
        ("cuatrimestral", "cuatrimestral"),
        ("trimestral", "trimestral"),
        ("bimestral", "bimestral"),
        ("semestral", "semestral"),
        ("semestre", "semestral"),
        ("anualidad", "anual"),
        ("anualmente", "anual"),
        ("anual", "anual"),
        ("mensual", "mensual"),
    )
    for phrase, period in options:
        if phrase in folded:
            return period
    return default


def _date(text):
    numeric = re.search(r"\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b", text)
    if numeric:
        day, month, year = map(int, numeric.groups())
        try:
            return datetime(year, month, day).strftime("%Y-%m-%d")
        except ValueError:
            return ""

    months = {
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4,
        "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
        "septiembre": 9, "setiembre": 9, "octubre": 10,
        "noviembre": 11, "diciembre": 12,
    }
    folded = _fold(text)
    for month_name, month in months.items():
        match = re.search(rf"\b(\d{{1,2}})\s+de\s+{month_name}\s+de\s+(\d{{4}})\b", folded)
        if match:
            try:
                return datetime(int(match.group(2)), month, int(match.group(1))).strftime("%Y-%m-%d")
            except ValueError:
                return ""
    return ""


def _amount_after(text, phrase):
    folded = _fold(text)
    target = _fold(phrase)
    match = re.search(rf"\b{re.escape(target)}\b", folded)
    if not match:
        return None, None

    tail = text[match.end():]
    tail = re.split(r"[.;]", tail, maxsplit=1)[0]
    amount = _money(tail)
    if amount is None:
        return None, None

    return amount, _period(tail, "mensual")


def _expense(text, aliases, default):
    for alias in sorted(aliases, key=len, reverse=True):
        value, period = _amount_after(text, alias)
        if value is not None:
            return value, period or default
    return None, None


def _relation_in(segment):
    folded = _fold(segment)
    for alias, label in RELATIONS.items():
        if re.search(rf"\b{re.escape(_fold(alias))}\b", folded):
            return alias, label
    return None, None


def _name_in(segment):
    explicit = re.search(
        r"(?:se llama|nombre es)\s+([A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:\s+[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+){0,4})",
        segment,
        re.I,
    )
    if not explicit:
        return ""
    name = re.split(
        r"\s+(?:tiene|trabaja|gana|ingresa|aporta|da|es responsable|se hace cargo)\b",
        explicit.group(1),
        maxsplit=1,
        flags=re.I,
    )[0]
    return _title(name)


def _money_after_verb(segment, verbs):
    folded = _fold(segment)
    for verb in verbs:
        match = re.search(rf"\b{re.escape(_fold(verb))}\b", folded)
        if not match:
            continue
        amount = _money(segment[match.end():])
        if amount is not None:
            return amount
    return None


def interpret_dictation(text):
    original = _clean(text)
    folded = _fold(original)

    data = {"dictado_original": original}
    family = []
    incomes = []
    extras = []
    detected = []
    warnings = []

    if not original:
        return {
            "data": data,
            "family_members": [],
            "income_rows": [],
            "extra_expenses": [],
            "detected": [],
            "warnings": ["No se recibió texto para interpretar."],
        }

    if "renovacion" in folded:
        data["solicitud_tipo"] = "Renovación"
        detected.append("Solicitud: renovación")
    elif "solicitud nueva" in folded or "nueva solicitud" in folded:
        data["solicitud_tipo"] = "Nueva"
        detected.append("Solicitud: nueva")

    if "matutino" in folded or "turno de la manana" in folded:
        data["turno"] = "Matutino"
        detected.append("Turno: matutino")
    elif "vespertino" in folded or "turno de la tarde" in folded:
        data["turno"] = "Vespertino"
        detected.append("Turno: vespertino")

    student = re.search(
        r"(?:alumno|alumna|estudiante|niño|niña)\s+(?:se llama\s+)?"
        r"([A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+(?:\s+[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+){1,4})",
        original,
        re.I,
    )
    if student:
        value = re.split(
            r"\s+(?:tiene|vive|cursa|solicita|turno|fecha)\b",
            student.group(1),
            maxsplit=1,
            flags=re.I,
        )[0]
        parts = _title(value).split()
        if len(parts) >= 3:
            data["nombre_alumno"] = " ".join(parts[:-2])
            data["apellido_paterno_alumno"] = parts[-2]
            data["apellido_materno_alumno"] = parts[-1]
        elif len(parts) == 2:
            data["nombre_alumno"] = parts[0]
            data["apellido_paterno_alumno"] = parts[1]
        detected.append("Nombre del alumno")

    age = re.search(r"(?:tiene|edad(?: de)?)\s+(\d{1,2})\s+años", folded)
    if age:
        data["edad"] = age.group(1)
        detected.append("Edad del alumno")

    grade = re.search(r"(?:grado|solicita)\s+([1-6])\s*(?:°|º|o)?", folded)
    if grade:
        data["grado"] = grade.group(1) + "°"
        detected.append("Grado")

    interview = _date(original)
    if "fecha de entrevista" in folded and interview:
        data["fecha"] = interview
        detected.append("Fecha de entrevista")

    scholarship = re.search(
        r"\bbeca(?: actual)?\s+(?:de\s+)?(\d{1,3}(?:[.,]\d+)?)\s*(?:%|por ciento)",
        folded,
    )
    if scholarship:
        data["beca_actual_pct"] = scholarship.group(1).replace(",", ".")
        detected.append("Beca actual")

    segments = [x.strip() for x in re.split(r"[.;\n]+", original) if x.strip()]
    for segment in segments:
        relation_alias, relation = _relation_in(segment)
        if not relation:
            continue

        name = _name_in(segment) or relation
        age_match = re.search(r"\b(\d{1,2})\s+años\b", segment, re.I)

        occupation = ""
        occupation_match = re.search(
            r"(?:trabaja como|ocupación(?: es)?|ocupacion(?: es)?|se dedica a)\s+"
            r"(.+?)(?=,|\by\b|\bgana\b|\bingresa\b|\baporta\b|$)",
            segment,
            re.I,
        )
        if occupation_match:
            occupation = _clean(occupation_match.group(1))

        responsible = bool(
            re.search(
                r"\b(responsable|se hace cargo|principal proveedor[ao]?|principal sostén|principal sosten)\b",
                segment,
                re.I,
            )
        )

        family.append({
            "nombre": name,
            "parentesco": relation,
            "edad": age_match.group(1) if age_match else "",
            "ocupacion": occupation,
            "responsable": responsible,
        })

        income = _money_after_verb(segment, ("gana", "ingresa", "percibe", "sueldo"))
        contribution = _money_after_verb(
            segment,
            ("aporta", "da", "apoya con", "coopera con", "contribuye con"),
        )

        if income is not None or contribution is not None:
            incomes.append({
                "integrante": name,
                "lugar_trabajo": "",
                "antiguedad": "",
                "puesto": occupation,
                "ingreso_mensual": "" if income is None else round(income, 2),
                "aportacion_mensual": "" if contribution is None else round(contribution, 2),
            })

    for field, aliases in EXPENSE_ALIASES.items():
        default = DEFAULT_PERIOD.get(field, "mensual")
        value, period = _expense(original, aliases, default)
        if value is None:
            continue
        data[field] = round(value, 2)
        data[field + "_periodo"] = period or default
        detected.append(f"{aliases[0]}: {value:g} ({period or default})")

    for concept, aliases in EXTRA_CONCEPTS.items():
        value, period = _expense(original, aliases, "mensual")
        if value is None:
            continue
        extras.append({
            "concepto": concept,
            "monto_mensual": round(value, 2),
            "periodicidad": period or "mensual",
            "detalle": "Detectado desde dictado; confirmar antes de autorizar.",
        })
        detected.append(f"{concept}: {value:g} ({period or 'mensual'})")

    if not family:
        warnings.append("No se identificaron integrantes familiares con suficiente claridad.")
    if not incomes:
        warnings.append("No se identificaron ingresos o aportaciones con suficiente claridad.")

    return {
        "data": data,
        "family_members": family,
        "income_rows": incomes,
        "extra_expenses": extras,
        "detected": detected,
        "warnings": warnings,
    }

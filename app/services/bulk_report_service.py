from __future__ import annotations

import statistics
from decimal import Decimal, InvalidOperation
from io import BytesIO
from urllib.parse import quote_plus

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter

from app.services.report_service import field_payload
from app.services.socioeconomic_metrics import calculate_metrics


DARK = "315500"
WHITE = "FFFFFF"

EXPENSE_FIELDS = [
    ("predial", "Predial"),
    ("renta", "Renta"),
    ("luz", "Luz"),
    ("agua", "Agua"),
    ("telefono_gasto", "TelÃ©fono"),
    ("gas", "Gas"),
    ("alimentos", "Alimentos"),
    ("automovil", "AutomÃ³vil"),
    ("pasajes", "Pasajes"),
    ("colegiaturas", "Colegiaturas"),
    ("vestido", "Vestido"),
    ("medico_medicinas", "MÃ©dico y medicinas"),
    ("muebles_hogar", "Muebles del hogar"),
    ("creditos_personales", "CrÃ©ditos personales"),
    ("otros_gastos", "Otros gastos"),
]


def _header(cell):
    cell.fill = PatternFill("solid", fgColor=DARK)
    cell.font = Font(color=WHITE, bold=True)
    cell.alignment = Alignment(horizontal="center", vertical="center")


def _autowidth(ws, max_width=48):
    for cells in ws.columns:
        idx = cells[0].column
        length = max(len(str(c.value or "")) for c in cells)
        ws.column_dimensions[get_column_letter(idx)].width = min(
            max(length + 2, 10),
            max_width,
        )


def _number(value):
    if value is None:
        return None

    text = str(value).strip()
    if not text:
        return None

    folded = text.lower()

    if any(word in folded for word in ("ninguno", "ninguna", "no aplica")):
        return 0.0

    cleaned = "".join(ch for ch in text if ch.isdigit() or ch in ".,-")
    if not cleaned:
        return None

    if "," in cleaned and "." in cleaned:
        if cleaned.rfind(".") > cleaned.rfind(","):
            cleaned = cleaned.replace(",", "")
        else:
            cleaned = cleaned.replace(".", "").replace(",", ".")
    elif "," in cleaned:
        parts = cleaned.split(",")
        if len(parts[-1]) == 2:
            cleaned = "".join(parts[:-1]) + "." + parts[-1]
        else:
            cleaned = cleaned.replace(",", "")

    try:
        return float(Decimal(cleaned))
    except (InvalidOperation, ValueError):
        return None


def _confirmed(payload, key):
    item = payload.get("fields", {}).get(key, {})
    return item.get("confirmed") or item.get("detected") or ""


def _maps_url(payload):
    address = _confirmed(payload, "domicilio").strip()
    postal_code = _confirmed(payload, "codigo_postal").strip()

    query = ", ".join(part for part in (address, postal_code) if part)

    if not query:
        return ""

    return (
        "https://www.google.com/maps/search/?api=1&query="
        + quote_plus(query)
    )


def _analysis(study, payload):
    data = payload.get("analysis", {})

    income = data.get(
        "total_income",
        getattr(study, "total_income", 0) or 0,
    )
    expenses = data.get(
        "total_expenses",
        getattr(study, "total_expenses", 0) or 0,
    )
    household = data.get(
        "household_size",
        getattr(study, "household_size", 1) or 1,
    )
    final_fee = data.get(
        "final_fee",
        getattr(study, "final_fee", None),
    )

    return calculate_metrics(income, expenses, household), final_fee


def _sheet_name(base, used):
    invalid = '[]:*?/\\'
    name = "".join("_" if ch in invalid else ch for ch in base)[:31] or "Caso"
    original = name
    counter = 2

    while name in used:
        suffix = f"_{counter}"
        name = original[:31-len(suffix)] + suffix
        counter += 1

    used.add(name)
    return name


def _explicit_total_income(payload):
    value = _confirmed(payload, "total_ingresos")
    return _number(value) if value else None


def _explicit_total_expenses(expenses):
    values = [value for value in expenses.values() if value is not None]
    return sum(values) if values else None


def _add_hyperlink(cell, url, text="Abrir ubicaciÃ³n"):
    if not url:
        cell.value = ""
        return

    cell.value = text
    cell.hyperlink = url
    cell.style = "Hyperlink"


def build_bulk_workbook(studies, instance_path):
    wb = Workbook()

    stats_ws = wb.active
    stats_ws.title = "EstadÃ­sticas"

    rows = []

    series = {
        "Ingreso total": [],
        "Gasto total": [],
        "Cuota final": [],
    }

    for _, label in EXPENSE_FIELDS:
        series[label] = []

    for study in studies:
        payload = field_payload(instance_path, study.id)
        metrics, final_fee = _analysis(study, payload)

        expenses = {}

        for key, label in EXPENSE_FIELDS:
            value = _number(_confirmed(payload, key))
            expenses[key] = value

            if value is not None:
                series[label].append(value)

        explicit_income = _explicit_total_income(payload)
        explicit_expenses = _explicit_total_expenses(expenses)

        analysis = payload.get("analysis", {})

        income_for_stats = (
            explicit_income
            if explicit_income is not None
            else analysis.get("total_income")
        )

        expenses_for_stats = (
            explicit_expenses
            if explicit_expenses is not None
            else analysis.get("total_expenses")
        )

        if income_for_stats is not None:
            series["Ingreso total"].append(float(income_for_stats))

        if expenses_for_stats is not None:
            series["Gasto total"].append(float(expenses_for_stats))

        if final_fee not in (None, ""):
            series["Cuota final"].append(float(final_fee))

        rows.append(
            (
                study,
                payload,
                metrics,
                final_fee,
                expenses,
                _maps_url(payload),
            )
        )

    headers = [
        "Indicador",
        "Casos con dato",
        "Media",
        "Mediana",
        "MÃ­nimo",
        "MÃ¡ximo",
    ]

    for col, header in enumerate(headers, 1):
        stats_ws.cell(1, col, header)
        _header(stats_ws.cell(1, col))

    row_idx = 2

    for label, values in series.items():
        stats_ws.cell(row_idx, 1, label)
        stats_ws.cell(row_idx, 2, len(values))

        if values:
            stats_ws.cell(row_idx, 3, round(statistics.mean(values), 2))
            stats_ws.cell(row_idx, 4, round(statistics.median(values), 2))
            stats_ws.cell(row_idx, 5, round(min(values), 2))
            stats_ws.cell(row_idx, 6, round(max(values), 2))

            for col in range(3, 7):
                stats_ws.cell(row_idx, col).number_format = '$#,##0.00 "MXN"'

        row_idx += 1

    cases_ws = wb.create_sheet("Casos")

    case_headers = [
        "Folio",
        "Caso",
        "Estatus",
        "Turno",
        "Google Maps",
        "Ingreso total",
        "Gasto total",
        "Disponible",
        "Integrantes",
        "Ingreso per cÃ¡pita",
        "Disponible per cÃ¡pita",
        "Carga de gasto (%)",
        "Cuota final",
    ] + [label for _, label in EXPENSE_FIELDS]

    for col, header in enumerate(case_headers, 1):
        cases_ws.cell(1, col, header)
        _header(cases_ws.cell(1, col))

    for row_number, (
        study,
        payload,
        metrics,
        final_fee,
        expenses,
        maps_url,
    ) in enumerate(rows, 2):

        values = [
            study.folio,
            study.student_name,
            study.status,
            _confirmed(payload, "turno"),
            "",
            metrics.total_income,
            metrics.total_expenses,
            metrics.available,
            metrics.household_size,
            metrics.income_per_capita,
            metrics.available_per_capita,
            metrics.expense_burden_pct,
            final_fee if final_fee not in (None, "") else "",
        ] + [
            expenses[key] if expenses[key] is not None else ""
            for key, _ in EXPENSE_FIELDS
        ]

        for col, value in enumerate(values, 1):
            cases_ws.cell(row_number, col, value)

        _add_hyperlink(
            cases_ws.cell(row_number, 5),
            maps_url,
        )

        # Moneda: columnas F-K, cuota M y rubros N en adelante.
        for col in [6, 7, 8, 10, 11, 13]:
            cases_ws.cell(row_number, col).number_format = '$#,##0.00 "MXN"'

        for col in range(14, len(case_headers) + 1):
            cases_ws.cell(row_number, col).number_format = '$#,##0.00 "MXN"'

    used = {"EstadÃ­sticas", "Casos"}

    for (
        study,
        payload,
        metrics,
        final_fee,
        expenses,
        maps_url,
    ) in rows:

        ws = wb.create_sheet(
            _sheet_name(f"Caso_{study.id}_{study.student_name}", used)
        )

        ws["A1"] = f"{study.folio} - {study.student_name}"
        ws["A1"].font = Font(size=14, bold=True, color=DARK)
        ws.merge_cells("A1:D1")

        summary = [
            ("Ingreso total", metrics.total_income),
            ("Gasto total", metrics.total_expenses),
            ("Disponible", metrics.available),
            ("Integrantes", metrics.household_size),
            ("Ingreso per cÃ¡pita", metrics.income_per_capita),
            ("Disponible per cÃ¡pita", metrics.available_per_capita),
            ("Carga de gasto (%)", metrics.expense_burden_pct),
            (
                "Cuota final",
                final_fee if final_fee not in (None, "") else "Pendiente",
            ),
            ("Contexto humano", payload.get("context_notes", "")),
            ("Google Maps", ""),
        ]

        for row_number, (label, value) in enumerate(summary, 3):
            ws.cell(row_number, 1, label).font = Font(
                bold=True,
                color=DARK,
            )
            ws.cell(row_number, 2, value)

        _add_hyperlink(
            ws.cell(12, 2),
            maps_url,
        )

        start = 15

        for col, header in enumerate(
            ["Campo", "OCR", "Confirmado", "Confianza"],
            1,
        ):
            ws.cell(start, col, header)
            _header(ws.cell(start, col))

        for row_number, (name, item) in enumerate(
            payload.get("fields", {}).items(),
            start + 1,
        ):
            ws.cell(
                row_number,
                1,
                item.get("label") or name,
            )
            ws.cell(
                row_number,
                2,
                item.get("raw_detected") or item.get("detected") or "",
            )
            ws.cell(
                row_number,
                3,
                item.get("confirmed") or "",
            )
            ws.cell(
                row_number,
                4,
                round(float(item.get("confidence", 0)) * 100, 2),
            )

    for ws in wb.worksheets:
        ws.freeze_panes = "A2"
        _autowidth(ws)

    output = BytesIO()
    wb.save(output)
    output.seek(0)

    return output

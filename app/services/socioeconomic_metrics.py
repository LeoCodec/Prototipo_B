from __future__ import annotations

import re
from dataclasses import asdict, dataclass


@dataclass
class Metrics:
    total_income: float
    total_expenses: float
    household_size: int
    available: float
    income_per_capita: float
    available_per_capita: float
    expense_burden_pct: float

    def as_dict(self):
        return asdict(self)


def parse_money(value) -> float:
    if value is None:
        return 0.0

    if isinstance(value, (int, float)):
        return float(value)

    text = str(value).strip()
    if not text:
        return 0.0

    # Acepta $ 1,250.50 o 1250
    text = re.sub(r"[^\d,.\-]", "", text)

    if "," in text and "." not in text:
        # En estos formatos, la coma suele ser separador de miles.
        text = text.replace(",", "")
    else:
        text = text.replace(",", "")

    try:
        return float(text)
    except ValueError:
        return 0.0


def calculate_metrics(total_income, total_expenses, household_size):
    income = max(parse_money(total_income), 0.0)
    expenses = max(parse_money(total_expenses), 0.0)

    try:
        n = int(household_size or 1)
    except (TypeError, ValueError):
        n = 1

    n = max(n, 1)

    available = income - expenses
    income_per_capita = income / n
    available_per_capita = available / n
    burden = (expenses / income * 100.0) if income > 0 else 0.0

    return Metrics(
        total_income=round(income, 2),
        total_expenses=round(expenses, 2),
        household_size=n,
        available=round(available, 2),
        income_per_capita=round(income_per_capita, 2),
        available_per_capita=round(available_per_capita, 2),
        expense_burden_pct=round(burden, 2),
    )


def descriptive_findings(metrics: Metrics) -> list[str]:
    findings = []

    if metrics.total_income == 0 and metrics.total_expenses > 0:
        findings.append(
            "Hay gastos registrados y el ingreso total es cero; "
            "conviene revisar la captura o confirmacion."
        )

    if metrics.total_income > 0:
        findings.append(
            f"El gasto registrado representa "
            f"{metrics.expense_burden_pct:.2f}% del ingreso mensual."
        )

    if metrics.available < 0:
        findings.append(
            "Los gastos registrados superan al ingreso mensual registrado."
        )
    elif metrics.available >= 0:
        findings.append(
            f"El disponible mensual calculado es "
            f"${metrics.available:,.2f}."
        )

    findings.append(
        f"El ingreso mensual per capita calculado es "
        f"${metrics.income_per_capita:,.2f}."
    )

    return findings

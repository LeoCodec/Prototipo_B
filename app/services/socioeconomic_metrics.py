from dataclasses import dataclass, asdict


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


def calculate_metrics(total_income, total_expenses, household_size):
    income = max(float(total_income or 0), 0.0)
    expenses = max(float(total_expenses or 0), 0.0)
    n = max(int(household_size or 1), 1)

    available = income - expenses
    ipc = income / n
    dpc = available / n
    burden = (expenses / income * 100.0) if income > 0 else 0.0

    return Metrics(
        total_income=round(income, 2),
        total_expenses=round(expenses, 2),
        household_size=n,
        available=round(available, 2),
        income_per_capita=round(ipc, 2),
        available_per_capita=round(dpc, 2),
        expense_burden_pct=round(burden, 2),
    )

def economic_summary(total_income, total_expenses, household_size):
    total_income = float(total_income or 0)
    total_expenses = float(total_expenses or 0)
    household_size = max(int(household_size or 1), 1)

    available = total_income - total_expenses
    ipc = total_income / household_size
    dpc = available / household_size
    expense_load = (total_expenses / total_income * 100) if total_income > 0 else None

    return {
        "total_income": total_income,
        "total_expenses": total_expenses,
        "available": available,
        "household_size": household_size,
        "income_per_capita": ipc,
        "available_per_capita": dpc,
        "expense_load": expense_load,
    }

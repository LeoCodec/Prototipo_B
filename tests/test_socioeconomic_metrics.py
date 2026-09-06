import unittest

from app.services.socioeconomic_metrics import calculate_metrics


class MetricsTest(unittest.TestCase):
    def test_standard_case(self):
        m = calculate_metrics(10000, 7000, 4)
        self.assertEqual(m.available, 3000.0)
        self.assertEqual(m.income_per_capita, 2500.0)
        self.assertEqual(m.available_per_capita, 750.0)
        self.assertEqual(m.expense_burden_pct, 70.0)

    def test_zero_income(self):
        m = calculate_metrics(0, 500, 2)
        self.assertEqual(m.expense_burden_pct, 0.0)
        self.assertEqual(m.available, -500.0)

    def test_household_floor(self):
        m = calculate_metrics(9000, 3000, 0)
        self.assertEqual(m.household_size, 1)


if __name__ == "__main__":
    unittest.main()

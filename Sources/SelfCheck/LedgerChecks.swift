import Foundation
import FinanceCore

func dec(_ s: String) -> Decimal { Decimal(string: s)! }
func day(_ s: String) -> Day { Day(s)! }

func runLedgerChecks() {
    var d = FinanceData.defaults()
    func cat(_ n: String, _ k: Kind) -> TxCategory { d.categories.first { $0.name == n && $0.kind == k }! }
    let salary = cat("Salary", .income), rent = cat("Rent", .expense), groceries = cat("Groceries", .expense), eating = cat("Eating out", .expense)
    d.transactions = [
        Transaction(date: day("2026-11-01"), amount: 2800, kind: .income, categoryId: salary.id, payee: "Employer"),
        Transaction(date: day("2026-11-01"), amount: 750, kind: .expense, categoryId: rent.id, payee: "Landlord"),
        Transaction(date: day("2026-11-03"), amount: dec("40.10"), kind: .expense, categoryId: groceries.id, payee: "REWE"),
        Transaction(date: day("2026-11-10"), amount: 30, kind: .expense, categoryId: groceries.id, payee: "Rewe "),
        Transaction(date: day("2026-11-20"), amount: 20, kind: .expense, categoryId: groceries.id, payee: "rewe"),
        Transaction(date: day("2026-11-05"), amount: dec("12.50"), kind: .expense, categoryId: eating.id, payee: "Pizza"),
        Transaction(date: day("2026-11-12"), amount: dec("12.50"), kind: .expense, categoryId: eating.id),
        Transaction(date: day("2026-10-15"), amount: 99, kind: .expense, categoryId: groceries.id, payee: "Edeka"),
    ]
    let hid = UUID()
    d.trades = [
        Trade(holdingId: hid, date: day("2026-11-02"), side: .buy, amount: 400, units: 3, pricePerUnit: dec("133.33")),
        Trade(holdingId: hid, date: day("2026-11-20"), side: .sell, amount: 100, units: 1, pricePerUnit: 100),
    ]
    let nov = YearMonth(year: 2026, month: 11)

    precondition(monthSummary(d, nov) == MonthSummary(income: 2800, spent: dec("865.10"), invested: 300))
    precondition(monthSummary(d, nov).left == dec("1634.90"))
    let cs = categoryStats(d, nov, kind: .expense)
    precondition(cs.map(\.name) == ["Rent", "Groceries", "Eating out"])
    precondition(cs[1].count == 3 && cs[1].total == dec("90.10") && cs[1].id == groceries.id)
    precondition(cs[2].count == 2 && cs[2].total == 25)
    precondition(categoryStats(d, nov, kind: .income).map(\.name) == ["Salary"])
    let ps = payeeStats(d, nov)
    precondition(ps.first(where: { $0.id == "rewe" })?.count == 3)
    precondition(ps.first(where: { $0.id == "rewe" })?.payee == "rewe")
    precondition(!ps.contains { $0.id == "employer" } && !ps.contains { $0.id == "edeka" })
    precondition(ps.first?.id == "landlord")
    precondition(lastCategory(forPayee: " REWE", in: d) == groceries.id)
    precondition(lastCategory(forPayee: "nobody", in: d) == nil)
    precondition(payeeSuggestions("re", in: d) == ["rewe"])
    precondition(payeeSuggestions("", in: d).count == 5)
    precondition(categoryStats(d, nil, kind: .expense).first(where: { $0.name == "Groceries" })?.count == 4)

    // cumulative spending per day of month
    let cum = cumulativeSpending(d, nov, through: 12)
    precondition(cum.count == 12 && cum[0] == 750 && cum[2] == dec("790.10") && cum[4] == dec("802.60") && cum[11] == dec("845.10"))
    precondition(cumulativeSpending(d, nov, through: 40).count == 30)
    let oct = cumulativeSpending(d, YearMonth(year: 2026, month: 10), through: 31)
    precondition(oct.count == 31 && oct[13] == 0 && oct[14] == 99 && oct[30] == 99)
}

import Foundation
import FinanceCore

func runRecurringChecks() {
    func rule(_ f: Frequency, _ dom: Int, _ start: String, end: String? = nil, last: String? = nil, target: RuleTarget = .transaction) -> RecurringRule {
        RecurringRule(target: target, amount: 10, frequency: f, dayOfMonth: dom, startDate: day(start),
                      endDate: end.map(day), lastGenerated: last.map(day), kind: .expense, categoryId: UUID())
    }
    func occ(_ r: RecurringRule, _ through: String) -> [String] { occurrences(of: r, through: day(through)).map(\.description) }

    precondition(occ(rule(.monthly, 31, "2026-01-15"), "2026-04-30") == ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"])
    precondition(occ(rule(.monthly, 2, "2026-03-10"), "2026-05-01") == ["2026-04-02"])
    precondition(occ(rule(.yearly, 29, "2024-02-29"), "2026-03-01") == ["2024-02-29", "2025-02-28", "2026-02-28"])
    precondition(occ(rule(.monthly, 1, "2026-01-01", end: "2026-02-15"), "2026-06-01").count == 2)
    precondition(occ(rule(.monthly, 1, "2026-01-01", last: "2026-05-01"), "2026-06-01") == ["2026-06-01"])
    precondition(occ(rule(.monthly, 1, "2027-01-01"), "2026-06-01").isEmpty)

    // weekly: every 7 days from the start date (2026-11-02 is a Monday)
    precondition(occ(rule(.weekly, 1, "2026-11-02"), "2026-11-26") == ["2026-11-02", "2026-11-09", "2026-11-16", "2026-11-23"])
    precondition(occ(rule(.weekly, 1, "2026-11-02", last: "2026-11-16"), "2026-11-30") == ["2026-11-23", "2026-11-30"])
    // every 3 months, counted from the start month, day clamped
    precondition(occ(rule(.quarterly, 31, "2026-01-10"), "2026-12-31") == ["2026-01-31", "2026-04-30", "2026-07-31", "2026-10-31"])
    precondition(occ(rule(.quarterly, 15, "2025-11-20"), "2026-11-26") == ["2026-02-15", "2026-05-15", "2026-08-15", "2026-11-15"])

    // idempotent catch-up: last generated 2026-08-02, opened 2026-11-26 twice
    var d = FinanceData.defaults()
    let msci = Holding(name: "MSCI World", ticker: "EUNL.DE")
    d.holdings = [msci]
    let plan = RecurringRule(target: .trade, amount: 400, frequency: .monthly, dayOfMonth: 2, startDate: day("2026-01-02"),
                             lastGenerated: day("2026-08-02"), holdingId: msci.id)
    d.rules = [plan]
    precondition(generateRecurring(&d, today: day("2026-11-26")) == 3)
    precondition(generateRecurring(&d, today: day("2026-11-26")) == 0)
    precondition(d.trades.map(\.date.description) == ["2026-09-02", "2026-10-02", "2026-11-02"])
    precondition(d.trades.allSatisfy { $0.unitsEstimated && $0.units == 0 && $0.recurringId == plan.id && $0.amount == 400 && $0.side == .buy && $0.holdingId == msci.id })
    precondition(d.rules[0].lastGenerated == day("2026-11-02"))
    d.trades.removeFirst()
    precondition(generateRecurring(&d, today: day("2026-11-26")) == 0)

    // transaction rule copies kind, category, payee
    let rent = d.categories[0]
    d.rules = [RecurringRule(target: .transaction, amount: 750, frequency: .monthly, dayOfMonth: 1, startDate: day("2026-11-01"),
                             kind: .expense, categoryId: rent.id, payee: "Landlord")]
    precondition(generateRecurring(&d, today: day("2026-11-26")) == 1)
    let t = d.transactions[0]
    precondition(t.amount == 750 && t.kind == .expense && t.categoryId == rent.id && t.payee == "Landlord" && t.recurringId == d.rules[0].id && t.date == day("2026-11-01"))
}

func runSettingsChecks() {
    var d = FinanceData.defaults()
    let groceries = d.categories[1], other = d.categories[8]
    d.transactions = [Transaction(date: day("2026-11-02"), amount: 5, kind: .expense, categoryId: groceries.id)]
    d.rules = [RecurringRule(target: .transaction, amount: 5, frequency: .monthly, dayOfMonth: 1, startDate: day("2026-01-01"), kind: .expense, categoryId: groceries.id)]
    deleteCategory(groceries.id, moveTo: other.id, &d)
    precondition(d.category(groceries.id) == nil && d.categories.count == 12)
    precondition(d.transactions[0].categoryId == other.id && d.rules[0].categoryId == other.id)

    let r = RecurringRule(target: .transaction, amount: 5, frequency: .monthly, dayOfMonth: 2, startDate: day("2026-01-02"), lastGenerated: day("2026-11-02"))
    precondition(nextDue(r, after: day("2026-11-26")) == day("2026-12-02"))
    let y = RecurringRule(target: .transaction, amount: 5, frequency: .yearly, dayOfMonth: 15, startDate: day("2027-03-15"))
    precondition(nextDue(y, after: day("2026-11-26")) == day("2027-03-15"))
    let ended = RecurringRule(target: .transaction, amount: 5, frequency: .monthly, dayOfMonth: 1, startDate: day("2026-01-01"), endDate: day("2026-06-30"), lastGenerated: day("2026-06-01"))
    // the Settings backfill warning: plan on the 2nd from 2026-06-02, saved on 2026-11-26
    let plan = RecurringRule(target: .trade, amount: 400, frequency: .monthly, dayOfMonth: 2, startDate: day("2026-06-02"))
    precondition(occurrences(of: plan, through: day("2026-11-26")).count == 6)
    precondition(nextDue(ended, after: day("2026-11-26")) == nil)
}

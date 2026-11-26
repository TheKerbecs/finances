import Foundation
import FinanceCore

func runAnalyticsChecks() {
    var d = FinanceData.defaults()
    func cat(_ n: String, _ k: Kind) -> UUID { d.categories.first { $0.name == n && $0.kind == k }!.id }
    let salary = cat("Salary", .income), subs = cat("Subscriptions", .expense), groceries = cat("Groceries", .expense), rent = cat("Rent", .expense)
    let h = Holding(name: "MSCI", ticker: "EUNL.DE")
    d.holdings = [h]
    d.rules = [
        RecurringRule(target: .transaction, amount: 2400, frequency: .monthly, dayOfMonth: 28, startDate: day("2026-10-28"), kind: .income, categoryId: salary, payee: "Employer"),
        RecurringRule(target: .transaction, amount: 750, frequency: .monthly, dayOfMonth: 1, startDate: day("2026-11-01"), kind: .expense, categoryId: rent, payee: "Landlord"),
        RecurringRule(target: .transaction, amount: dec("12.99"), frequency: .monthly, dayOfMonth: 30, startDate: day("2026-11-01"), kind: .expense, categoryId: subs, payee: "Netflix"),
        RecurringRule(target: .transaction, amount: 120, frequency: .yearly, dayOfMonth: 15, startDate: day("2026-03-15"), kind: .expense, categoryId: subs, payee: "Cloud"),
        RecurringRule(target: .trade, amount: 400, frequency: .monthly, dayOfMonth: 2, startDate: day("2026-11-02"), holdingId: h.id),
    ]
    d.transactions = [Transaction(date: day("2026-11-10"), amount: 60, kind: .expense, categoryId: groceries, payee: "Rewe")]
    generateRecurring(&d, today: day("2026-11-26"))   // Oct salary, Nov rent, Nov plan buy, Mar cloud
    let nov = YearMonth(year: 2026, month: 11)

    // forecast on Nov 26: salary (28th) and Netflix (30th) still to come
    let f = forecast(d, nov, today: day("2026-11-26"))
    precondition(f.received == 0 && f.expectedIncome == 2400)
    precondition(f.spentFixed == 750 && f.spentFlexible == 60 && f.scheduledBills == dec("12.99"))
    precondition(f.invested == 400 && f.plannedInvesting == 0)
    precondition(f.left == 2400 - 750 - 60 - dec("12.99") - 400)
    precondition(f.upcoming.map(\.date.description) == ["2026-11-28", "2026-11-30"] && f.upcoming.map(\.title) == ["Employer", "Netflix"])
    precondition(f.daysRemaining == 5 && f.perDay == roundTo(f.left / 5, 2))

    // a future month: everything is still to come
    let dec26 = forecast(d, YearMonth(year: 2026, month: 12), today: day("2026-11-26"))
    precondition(dec26.received == 0 && dec26.expectedIncome == 2400 && dec26.scheduledBills == 750 + dec("12.99") && dec26.plannedInvesting == 400)
    precondition(dec26.perDay == nil)
    // a past month: nothing upcoming, actuals only
    let oct = forecast(d, YearMonth(year: 2026, month: 10), today: day("2026-11-26"))
    precondition(oct.upcoming.isEmpty && oct.received == 2400 && oct.left == 2400)
    // the yearly rule shows up in its month only
    let mar27 = forecast(d, YearMonth(year: 2027, month: 3), today: day("2026-11-26"))
    precondition(mar27.scheduledBills == 750 + dec("12.99") + 120)

    // fixed costs normalized to a month
    let fc = fixedCosts(d, today: day("2026-11-26"))
    precondition(fc.map(\.title) == ["Landlord", "Netflix", "Cloud"])
    precondition(fc[2].perMonth == 10 && fc[2].perYear == 120 && fc[1].perYear == dec("155.88"))
    let weekly = RecurringRule(target: .transaction, amount: 30, frequency: .weekly, dayOfMonth: 1, startDate: day("2026-01-05"), kind: .expense, categoryId: groceries)
    precondition(monthlyEquivalent(weekly) == 130 && monthlyEquivalent(RecurringRule(target: .transaction, amount: 90, frequency: .quarterly, dayOfMonth: 1, startDate: day("2026-01-01"))) == 30)

    // period stats, averages, savings rate
    let both = categoryStats(d, from: YearMonth(year: 2026, month: 10), to: nov, kind: .income)
    precondition(both.first?.total == 2400 && both.first?.count == 1)
    precondition(averagePerMonth(d, categoryId: groceries, before: YearMonth(year: 2026, month: 12), months: 6) == 10)
    precondition(savingsRate(MonthSummary(income: 2000, spent: 1500, invested: 300)) == 25)
    precondition(savingsRate(MonthSummary(income: 0, spent: 10, invested: 0)) == nil)

    // cash flow over a period: fixed = from recurring rules, flexible = one-off
    let cf = cashFlow(d, from: nov, to: nov)
    precondition(cf.income == 0 && cf.fixed == 750 && cf.flexible == 60 && cf.invested == 400)

    // daily spending and weekdays (2026-11-26 is a Thursday)
    precondition(day("2026-11-26").weekday == 4 && day("2026-11-29").weekday == 7 && day("2026-11-30").weekday == 1)
    let daily = dailySpending(d, from: day("2026-11-01"), to: day("2026-11-30"))
    precondition(daily[day("2026-11-01")] == 750 && daily[day("2026-11-10")] == 60 && daily[day("2026-11-02")] == nil)
    // one-off spending only: rent (recurring) drops out
    let flex = dailySpending(d, from: day("2026-11-01"), to: day("2026-11-30"), includeRecurring: false)
    precondition(flex[day("2026-11-01")] == nil && flex[day("2026-11-10")] == 60)
}

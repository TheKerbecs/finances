import Foundation
import FinanceCore

func runAccountChecks() {
    // data saved before accounts existed still loads
    let old = #"{"version":1,"categories":[],"transactions":[],"holdings":[],"trades":[],"rules":[]}"#
    let decoded = try! JSONDecoder().decode(FinanceData.self, from: Data(old.utf8))
    precondition(decoded.accounts.isEmpty)

    var d = FinanceData.defaults()
    let groceries = d.categories[1].id, salary = d.categories.first { $0.kind == .income }!.id
    let h = Holding(name: "MSCI", ticker: "EUNL.DE")
    d.holdings = [h]
    var bank = Account(name: "Checking", isMain: true, paysInvesting: true)
    bank.checkins = [Checkin(date: day("2026-11-20"), balance: 2000), Checkin(date: day("2026-11-12"), balance: 2200)]   // unsorted on purpose
    let tr = Account(name: "Broker cash", isMain: false, paysInvesting: false,
                     checkins: [Checkin(date: day("2026-11-01"), balance: 500)])
    d.accounts = [bank, tr]
    d.transactions = [
        Transaction(date: day("2026-11-12"), amount: 30, kind: .expense, categoryId: groceries),   // same day as check-in: already in it
        Transaction(date: day("2026-11-15"), amount: 100, kind: .expense, categoryId: groceries),
        Transaction(date: day("2026-11-22"), amount: 40, kind: .expense, categoryId: groceries),
        Transaction(date: day("2026-11-24"), amount: 1000, kind: .income, categoryId: salary),
    ]
    d.trades = [Trade(holdingId: h.id, date: day("2026-11-23"), side: .buy, amount: 400, units: 3, pricePerUnit: dec("133.33"))]
    d.rules = [RecurringRule(target: .transaction, amount: dec("12.99"), frequency: .monthly, dayOfMonth: 30, startDate: day("2026-11-30"),
                             kind: .expense, categoryId: groceries, payee: "Netflix"),
               RecurringRule(target: .trade, amount: 50, frequency: .monthly, dayOfMonth: 28, startDate: day("2026-11-28"), holdingId: h.id)]

    precondition(d.accounts[0].latest == Checkin(date: day("2026-11-20"), balance: 2000))
    // expected today = 2000 − 40 − 400 (pays investing) + 1000
    precondition(expectedBalance(d, d.accounts[0], at: day("2026-11-26")) == 2560)
    // without the investing switch the buy doesn't count
    var noInvest = d.accounts[0]; noInvest.paysInvesting = false
    precondition(expectedBalance(d, noInvest, at: day("2026-11-26")) == 2960)
    // non-main account: entries don't touch it
    precondition(expectedBalance(d, d.accounts[1], at: day("2026-11-26")) == 500)
    precondition(expectedBalance(d, Account(name: "x", isMain: true, paysInvesting: false), at: day("2026-11-26")) == nil)

    // between the two check-ins: 2200 − 100 logged = 2100 expected, bank says 2000 → 100 not logged
    let u = unlogged(d, d.accounts[0])!
    precondition(u.amount == 100 && u.from == day("2026-11-12") && u.to == day("2026-11-20"))
    precondition(unlogged(d, d.accounts[1]) == nil)

    // month end: 2560 − 12,99 Netflix − 50 savings plan
    precondition(projectedMonthEnd(d, d.accounts[0], today: day("2026-11-26")) == 2560 - dec("12.99") - 50)
    precondition(projectedMonthEnd(d, d.accounts[1], today: day("2026-11-26")) == 500)

    // net worth = expected balances + portfolio (worth falls back to put in without a price)
    precondition(netWorth(d, today: day("2026-11-26")) == 2560 + 500 + 400)

    // a new entry form with "Repeats" becomes a rule
    let r = ruleForRepeat(.monthly, date: day("2026-11-30"), amount: 9, kind: .expense, categoryId: groceries, payee: "Spotify")
    precondition(r.dayOfMonth == 30 && r.startDate == day("2026-11-30") && r.target == .transaction && r.payee == "Spotify")
}

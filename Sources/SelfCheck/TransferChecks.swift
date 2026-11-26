import Foundation
import FinanceCore

func runTransferChecks() {
    // older files (no transfers, no accountId fields) still load
    let old = #"{"version":1,"categories":[],"transactions":[{"id":"6E8571CC-525D-4E9D-9120-0EC6ABBE8FC9","date":"2026-11-02","amount":5,"kind":"expense","categoryId":"5A84CEA6-8626-4DFE-BAE5-A86400A3996C"}],"holdings":[],"trades":[],"rules":[],"accounts":[]}"#
    let o = try! JSONDecoder().decode(FinanceData.self, from: Data(old.utf8))
    precondition(o.transfers.isEmpty && o.transactions[0].accountId == nil)

    var d = FinanceData.defaults()
    let groceries = d.categories[1].id
    let h = Holding(name: "MSCI", ticker: "EUNL.DE")
    d.holdings = [h]
    let bank = Account(name: "Checking", isMain: true, paysInvesting: false, checkins: [Checkin(date: day("2026-11-01"), balance: 1000)])
    let card = Account(name: "Credit card", isMain: false, paysInvesting: false, checkins: [Checkin(date: day("2026-11-01"), balance: 0)])
    let tr = Account(name: "Broker", isMain: false, paysInvesting: true, checkins: [Checkin(date: day("2026-11-01"), balance: 100)])
    d.accounts = [bank, card, tr]
    d.transactions = [
        Transaction(date: day("2026-11-05"), amount: 50, kind: .expense, categoryId: groceries),                       // default: main account
        Transaction(date: day("2026-11-06"), amount: 30, kind: .expense, categoryId: groceries, accountId: card.id),  // paid by card
    ]
    d.trades = [Trade(holdingId: h.id, date: day("2026-11-10"), side: .buy, amount: 400, units: 3, pricePerUnit: dec("133.33"))]   // default: TR
    d.transfers = [Transfer(date: day("2026-11-03"), amount: 500, from: bank.id, to: tr.id)]

    let at = day("2026-11-20")
    precondition(expectedBalance(d, bank, at: at) == 1000 - 50 - 500)
    precondition(expectedBalance(d, card, at: at) == -30)
    precondition(expectedBalance(d, tr, at: at) == 100 + 500 - 400)
    // a trade paid from an explicit account
    d.trades[0].accountId = bank.id
    precondition(expectedBalance(d, bank, at: at) == 1000 - 50 - 500 - 400 && expectedBalance(d, tr, at: at) == 600)
    d.trades[0].accountId = nil

    // transfers are neither income nor spending
    precondition(monthSummary(d, YearMonth(year: 2026, month: 11)) == MonthSummary(income: 0, spent: 80, invested: 400))

    // scheduled transfer: generated like other rules, shows as upcoming, moves the month-end balances
    let move = RecurringRule(target: .transfer, amount: 400, frequency: .monthly, dayOfMonth: 1, startDate: day("2026-11-01"),
                             fromAccountId: bank.id, toAccountId: tr.id)
    d.rules = [move]
    precondition(generateRecurring(&d, today: day("2026-11-27")) == 1)
    let t = d.transfers.first { $0.recurringId == move.id }!
    precondition(t.amount == 400 && t.from == bank.id && t.to == tr.id && t.date == day("2026-11-01"))
    let f = forecast(d, YearMonth(year: 2026, month: 12), today: day("2026-11-27"))
    precondition(f.upcoming.contains { $0.kind == .transfer && $0.amount == 400 } && f.left == 0)

    // rules booked to a specific account move that account's month-end balance
    var late = d
    late.rules.append(RecurringRule(target: .transaction, amount: 20, frequency: .monthly, dayOfMonth: 29, startDate: day("2026-11-29"),
                                    kind: .expense, categoryId: groceries, accountId: card.id))
    late.rules.append(RecurringRule(target: .transfer, amount: 100, frequency: .monthly, dayOfMonth: 30, startDate: day("2026-11-30"),
                                    fromAccountId: bank.id, toAccountId: card.id))
    let now = day("2026-11-27")
    precondition(projectedMonthEnd(late, card, today: now) == expectedBalance(late, card, at: now)! - 20 + 100)
    precondition(projectedMonthEnd(late, bank, today: now) == expectedBalance(late, bank, at: now)! - 100)

    // Repeats on the transfer form
    let r = ruleForTransfer(.monthly, date: day("2026-11-28"), amount: 400, from: bank.id, to: tr.id)
    precondition(r.target == .transfer && r.fromAccountId == bank.id && r.toAccountId == tr.id && r.dayOfMonth == 28)
}

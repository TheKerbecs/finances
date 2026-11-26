import Foundation

/// Due days strictly after `lastGenerated` (or from `startDate` inclusive), up to min(today, endDate).
/// Weekly: every 7 days from `startDate`. Monthly: `dayOfMonth` every month. Quarterly: every 3rd month
/// from `startDate.month`. Yearly: in `startDate.month`. Short months clamp to their last day.
public func occurrences(of r: RecurringRule, through today: Day) -> [Day] {
    let end = min(today, r.endDate ?? today)
    let after: (Day) -> Bool = { d in r.lastGenerated.map { d > $0 } ?? true }
    var out: [Day] = []
    if r.frequency == .weekly {
        var d = r.startDate
        while d <= end {
            if after(d) { out.append(d) }
            d = d.adding(days: 7)
        }
        return out
    }
    let step = r.frequency == .monthly ? 1 : r.frequency == .quarterly ? 3 : 12
    var m = r.startDate.yearMonth
    while m <= end.yearMonth {
        let d = Day.clamped(year: m.year, month: m.month, day: r.dayOfMonth)
        if d >= r.startDate, d <= end, after(d) { out.append(d) }
        for _ in 0..<step { m = m.next }
    }
    return out
}

/// Adds every missing entry for every rule and moves each rule's `lastGenerated` forward.
/// Savings plan buys start with 0 units, marked estimated, until a price fills them.
@discardableResult
public func generateRecurring(_ d: inout FinanceData, today: Day) -> Int {
    var created = 0
    for i in d.rules.indices {
        let r = d.rules[i]
        let days = occurrences(of: r, through: today)
        for day in days {
            switch r.target {
            case .transaction:
                guard let cat = r.categoryId else { continue }
                d.transactions.append(Transaction(date: day, amount: r.amount, kind: r.kind ?? .expense,
                                                  categoryId: cat, payee: r.payee, recurringId: r.id, accountId: r.accountId))
            case .trade:
                guard let h = r.holdingId else { continue }
                d.trades.append(Trade(holdingId: h, date: day, side: .buy, amount: r.amount, units: 0,
                                      pricePerUnit: 0, recurringId: r.id, unitsEstimated: true, accountId: r.accountId))
            case .transfer:
                guard let from = r.fromAccountId, let to = r.toAccountId else { continue }
                d.transfers.append(Transfer(date: day, amount: r.amount, from: from, to: to, note: r.payee, recurringId: r.id))
            }
            created += 1
        }
        if let last = days.last { d.rules[i].lastGenerated = last }
    }
    return created
}

/// The next day this rule adds an entry, after `today`. nil when it has ended.
public func nextDue(_ r: RecurringRule, after today: Day) -> Day? {
    var probe = r
    probe.lastGenerated = max(r.lastGenerated ?? today, today)
    return occurrences(of: probe, through: today.adding(days: 800)).first
}

/// Removes a category and moves its transactions and rules to `moveTo`.
public func deleteCategory(_ id: UUID, moveTo: UUID, _ d: inout FinanceData) {
    for i in d.transactions.indices where d.transactions[i].categoryId == id { d.transactions[i].categoryId = moveTo }
    for i in d.rules.indices where d.rules[i].categoryId == id { d.rules[i].categoryId = moveTo }
    d.categories.removeAll { $0.id == id }
}

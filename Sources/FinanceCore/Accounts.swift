import Foundation

/// A balance as seen in the bank or broker app on a day. Entries on that day are assumed to be in it.
public struct Checkin: Codable, Hashable, Sendable {
    public var date: Day
    public var balance: Decimal
    public init(date: Day, balance: Decimal) { self.date = date; self.balance = balance }
}

/// A bank or cash account tracked by check-ins.
/// `isMain`: default account for income and expenses without an account of their own.
/// `paysInvesting`: default account for buys and sells without an account of their own.
public struct Account: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isMain: Bool
    public var paysInvesting: Bool
    public var checkins: [Checkin]

    public init(id: UUID = UUID(), name: String, isMain: Bool, paysInvesting: Bool, checkins: [Checkin] = []) {
        self.id = id; self.name = name; self.isMain = isMain; self.paysInvesting = paysInvesting; self.checkins = checkins
    }

    public var latest: Checkin? { checkins.max { $0.date < $1.date } }
}

/// Whether an entry booked to `id` (nil = default) belongs to this account.
private func books(_ a: Account, _ id: UUID?, investing: Bool) -> Bool {
    id == a.id || (id == nil && (investing ? a.paysInvesting : a.isMain))
}

/// Money the app saw move through the account in (from, to].
private func flow(_ d: FinanceData, _ a: Account, after from: Day, through to: Day) -> Decimal {
    var sum: Decimal = 0
    for t in d.transactions where t.date > from && t.date <= to && books(a, t.accountId, investing: false) {
        sum += t.kind == .income ? t.amount : -t.amount
    }
    for t in d.trades where t.date > from && t.date <= to && books(a, t.accountId, investing: true) {
        sum += t.side == .buy ? -t.amount : t.amount
    }
    for t in d.transfers where t.date > from && t.date <= to {
        if t.from == a.id { sum -= t.amount }
        if t.to == a.id { sum += t.amount }
    }
    return sum
}

/// Last check-in on or before `day` plus what was logged since. nil without a check-in.
public func expectedBalance(_ d: FinanceData, _ a: Account, at day: Day) -> Decimal? {
    guard let c = a.checkins.filter({ $0.date <= day }).max(by: { $0.date < $1.date }) else { return nil }
    return c.balance + flow(d, a, after: c.date, through: day)
}

/// Spending the bank saw but the app didn't, between the last two check-ins. Positive = more went out than logged.
public func unlogged(_ d: FinanceData, _ a: Account) -> (amount: Decimal, from: Day, to: Day)? {
    let sorted = a.checkins.sorted { $0.date < $1.date }
    guard sorted.count >= 2 else { return nil }
    let older = sorted[sorted.count - 2], newer = sorted[sorted.count - 1]
    let expected = older.balance + flow(d, a, after: older.date, through: newer.date)
    return (expected - newer.balance, older.date, newer.date)
}

/// Expected balance today plus everything recurring still due this month that touches the account.
public func projectedMonthEnd(_ d: FinanceData, _ a: Account, today: Day) -> Decimal? {
    guard var b = expectedBalance(d, a, at: today) else { return nil }
    for u in forecast(d, today.yearMonth, today: today).upcoming {
        switch u.kind {
        case .income: if books(a, u.accountId, investing: false) { b += u.amount }
        case .bill: if books(a, u.accountId, investing: false) { b -= u.amount }
        case .investment: if books(a, u.accountId, investing: true) { b -= u.amount }
        case .transfer:
            if u.accountId == a.id { b -= u.amount }
            if u.toAccountId == a.id { b += u.amount }
        }
    }
    return b
}

/// Expected account balances plus the portfolio's current worth.
public func netWorth(_ d: FinanceData, today: Day) -> Decimal {
    let cash = d.accounts.compactMap { expectedBalance(d, $0, at: today) }.reduce(0, +)
    return cash + totals(d.holdings.map { position(of: $0, trades: d.trades) }).worth
}

/// The rule a new entry with "Repeats" set becomes: same day of month, starting on the entry's date.
public func ruleForRepeat(_ f: Frequency, date: Day, amount: Decimal, kind: Kind? = nil, categoryId: UUID? = nil,
                          payee: String? = nil, holdingId: UUID? = nil) -> RecurringRule {
    RecurringRule(target: holdingId == nil ? .transaction : .trade, amount: amount, frequency: f, dayOfMonth: date.day,
                  startDate: date, kind: holdingId == nil ? kind : nil, categoryId: categoryId, payee: payee, holdingId: holdingId)
}

/// The rule a transfer with "Repeats" set becomes.
public func ruleForTransfer(_ f: Frequency, date: Day, amount: Decimal, from: UUID, to: UUID, note: String? = nil) -> RecurringRule {
    RecurringRule(target: .transfer, amount: amount, frequency: f, dayOfMonth: date.day, startDate: date, payee: note,
                  fromAccountId: from, toAccountId: to)
}

import Foundation

public enum UpcomingKind: Sendable { case income, bill, investment, transfer }

/// A recurring entry that hasn't happened yet this month.
public struct Upcoming: Identifiable, Equatable, Sendable {
    public var id: String { "\(ruleId)-\(date)" }
    public var ruleId: UUID
    public var date: Day
    public var title: String
    public var amount: Decimal
    public var kind: UpcomingKind
    public var categoryId: UUID?
    /// The account it's booked to (for transfers: the one it leaves); nil = default.
    public var accountId: UUID? = nil
    /// Transfers only.
    public var toAccountId: UUID? = nil
}

public struct MonthForecast: Equatable, Sendable {
    public var received: Decimal = 0, spentFixed: Decimal = 0, spentFlexible: Decimal = 0, invested: Decimal = 0
    public var expectedIncome: Decimal = 0, scheduledBills: Decimal = 0, plannedInvesting: Decimal = 0
    public var upcoming: [Upcoming] = []
    public var daysRemaining = 0   // including today; 0 unless it's the current month

    public var income: Decimal { received + expectedIncome }
    public var fixed: Decimal { spentFixed + scheduledBills }
    public var investing: Decimal { invested + plannedInvesting }
    /// What will be left at the end of the month if nothing unplanned happens.
    public var left: Decimal { income - fixed - spentFlexible - investing }
    /// Spread of `left` over the remaining days; nil outside the current month or when nothing is left.
    public var perDay: Decimal? { daysRemaining > 0 && left > 0 ? roundTo(left / Decimal(daysRemaining), 2) : nil }
}

/// Recorded entries of the month plus every recurring entry still due after `today`.
public func forecast(_ d: FinanceData, _ m: YearMonth, today: Day) -> MonthForecast {
    var f = MonthForecast()
    for t in d.transactions where m.contains(t.date) {
        switch (t.kind, t.recurringId != nil) {
        case (.income, _): f.received += t.amount
        case (.expense, true): f.spentFixed += t.amount
        case (.expense, false): f.spentFlexible += t.amount
        }
    }
    for t in d.trades where m.contains(t.date) { f.invested += t.side == .buy ? t.amount : -t.amount }

    let first = Day(year: m.year, month: m.month, day: 1)
    let last = Day(year: m.year, month: m.month, day: m.dayCount)
    guard last > today else { return f }   // past month: actuals only
    let cutoff = max(today, first.adding(days: -1))
    if m == today.yearMonth { f.daysRemaining = m.dayCount - today.day + 1 }

    for r in d.rules {
        var probe = r
        probe.lastGenerated = max(r.lastGenerated ?? cutoff, cutoff)
        for day in occurrences(of: probe, through: last) {
            switch r.target {
            case .trade:
                f.plannedInvesting += r.amount
                f.upcoming.append(Upcoming(ruleId: r.id, date: day, title: d.holding(r.holdingId)?.name ?? "Savings plan",
                                           amount: r.amount, kind: .investment, accountId: r.accountId))
            case .transfer:
                let title = "\(d.account(r.fromAccountId)?.name ?? "?") → \(d.account(r.toAccountId)?.name ?? "?")"
                f.upcoming.append(Upcoming(ruleId: r.id, date: day, title: title, amount: r.amount, kind: .transfer,
                                           accountId: r.fromAccountId, toAccountId: r.toAccountId))
            case .transaction:
                let income = r.kind == .income
                if income { f.expectedIncome += r.amount } else { f.scheduledBills += r.amount }
                f.upcoming.append(Upcoming(ruleId: r.id, date: day, title: r.payee ?? d.category(r.categoryId)?.name ?? "Recurring",
                                           amount: r.amount, kind: income ? .income : .bill, categoryId: r.categoryId, accountId: r.accountId))
            }
        }
    }
    f.upcoming.sort { ($0.date, $0.title) < ($1.date, $1.title) }
    return f
}

/// A recurring amount as a monthly figure: weekly × 52 / 12, quarterly / 3, yearly / 12.
public func monthlyEquivalent(_ r: RecurringRule) -> Decimal {
    switch r.frequency {
    case .weekly: return roundTo(r.amount * 52 / 12, 2)
    case .monthly: return r.amount
    case .quarterly: return roundTo(r.amount / 3, 2)
    case .yearly: return roundTo(r.amount / 12, 2)
    }
}

public struct FixedCost: Identifiable, Equatable, Sendable {
    public var id: UUID   // rule id
    public var title: String
    public var categoryId: UUID?
    public var frequency: Frequency
    public var amount: Decimal
    public var perMonth: Decimal
    public var perYear: Decimal
}

/// Recurring expenses that haven't ended, in rule order.
public func fixedCosts(_ d: FinanceData, today: Day) -> [FixedCost] {
    d.rules.filter { $0.target == .transaction && $0.kind != .income && ($0.endDate.map { $0 >= today } ?? true) }.map { r in
        let pm = monthlyEquivalent(r)
        let py: Decimal = switch r.frequency {
        case .weekly: r.amount * 52
        case .monthly: r.amount * 12
        case .quarterly: r.amount * 4
        case .yearly: r.amount
        }
        return FixedCost(id: r.id, title: r.payee ?? d.category(r.categoryId)?.name ?? "Recurring", categoryId: r.categoryId,
                         frequency: r.frequency, amount: r.amount, perMonth: pm, perYear: py)
    }
}

/// Category totals over a range of months, largest first.
public func categoryStats(_ d: FinanceData, from: YearMonth, to: YearMonth, kind: Kind) -> [CategoryStat] {
    var byId: [UUID: CategoryStat] = [:]
    for t in d.transactions where t.kind == kind && t.date.yearMonth >= from && t.date.yearMonth <= to {
        byId[t.categoryId, default: CategoryStat(id: t.categoryId, name: d.category(t.categoryId)?.name ?? "Unknown", count: 0, total: 0)].count += 1
        byId[t.categoryId]!.total += t.amount
    }
    return byId.values.sorted { ($0.total, $1.name) > ($1.total, $0.name) }
}

/// Average monthly spending in a category over the `months` months before `before` (empty months count as 0).
public func averagePerMonth(_ d: FinanceData, categoryId: UUID, before: YearMonth, months: Int) -> Decimal {
    var from = before
    for _ in 0..<months { from = from.previous }
    let total = d.transactions.filter { $0.categoryId == categoryId && $0.kind == .expense && $0.date.yearMonth >= from && $0.date.yearMonth < before }
        .reduce(Decimal(0)) { $0 + $1.amount }
    return roundTo(total / Decimal(months), 2)
}

/// Share of income not spent (investing counts as saved), in percent. nil without income.
public func savingsRate(_ s: MonthSummary) -> Decimal? {
    s.income > 0 ? roundTo((s.income - s.spent) / s.income * 100, 1) : nil
}

public struct CashFlow: Equatable, Sendable {
    public var income: Decimal, fixed: Decimal, flexible: Decimal, invested: Decimal
    public var left: Decimal { income - fixed - flexible - invested }
}

/// Recorded money over a range of months. Fixed = expenses created by recurring rules.
public func cashFlow(_ d: FinanceData, from: YearMonth, to: YearMonth) -> CashFlow {
    var c = CashFlow(income: 0, fixed: 0, flexible: 0, invested: 0)
    for t in d.transactions where t.date.yearMonth >= from && t.date.yearMonth <= to {
        if t.kind == .income { c.income += t.amount } else if t.recurringId != nil { c.fixed += t.amount } else { c.flexible += t.amount }
    }
    for t in d.trades where t.date.yearMonth >= from && t.date.yearMonth <= to { c.invested += t.side == .buy ? t.amount : -t.amount }
    return c
}

/// Expense total per day in [from, to]; days without spending are absent.
/// `includeRecurring: false` keeps only one-off spending (no rent, subscriptions…).
public func dailySpending(_ d: FinanceData, from: Day, to: Day, includeRecurring: Bool = true) -> [Day: Decimal] {
    var out: [Day: Decimal] = [:]
    for t in d.transactions where t.kind == .expense && t.date >= from && t.date <= to && (includeRecurring || t.recurringId == nil) {
        out[t.date, default: 0] += t.amount
    }
    return out
}

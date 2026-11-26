import Foundation

public struct MonthSummary: Equatable, Sendable {
    public var income: Decimal, spent: Decimal, invested: Decimal
    public var left: Decimal { income - spent - invested }
    public init(income: Decimal, spent: Decimal, invested: Decimal) {
        self.income = income; self.spent = spent; self.invested = invested
    }
}

/// Invested = buy amounts minus sell amounts in that month.
public func monthSummary(_ d: FinanceData, _ m: YearMonth) -> MonthSummary {
    let tx = d.transactions.filter { m.contains($0.date) }
    let trades = d.trades.filter { m.contains($0.date) }
    return MonthSummary(
        income: tx.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount },
        spent: tx.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount },
        invested: trades.reduce(0) { $0 + ($1.side == .buy ? $1.amount : -$1.amount) })
}

public struct CategoryStat: Equatable, Identifiable, Sendable {
    public var id: UUID   // categoryId
    public var name: String
    public var count: Int
    public var total: Decimal
}

/// nil month = all time. Sorted by total, largest first. Categories without entries are left out.
public func categoryStats(_ d: FinanceData, _ m: YearMonth?, kind: Kind) -> [CategoryStat] {
    var byId: [UUID: CategoryStat] = [:]
    for t in d.transactions where t.kind == kind && (m?.contains(t.date) ?? true) {
        let name = d.category(t.categoryId)?.name ?? "Unknown"
        byId[t.categoryId, default: CategoryStat(id: t.categoryId, name: name, count: 0, total: 0)].count += 1
        byId[t.categoryId]!.total += t.amount
    }
    return byId.values.sorted { ($0.total, $1.name) > ($1.total, $0.name) }
}

public struct PayeeStat: Equatable, Identifiable, Sendable {
    public var id: String   // normalized key
    public var payee: String   // most recent spelling
    public var count: Int
    public var total: Decimal
}

public func normalizedPayee(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func payeeKey(_ t: Transaction) -> String? {
    guard let p = t.payee else { return nil }
    let k = normalizedPayee(p)
    return k.isEmpty ? nil : k
}

/// Expenses only, sorted by total, largest first.
public func payeeStats(_ d: FinanceData, _ m: YearMonth?) -> [PayeeStat] {
    var byKey: [String: (stat: PayeeStat, latest: Day)] = [:]
    for t in d.transactions where t.kind == .expense && (m?.contains(t.date) ?? true) {
        guard let k = payeeKey(t) else { continue }
        let spelling = t.payee!.trimmingCharacters(in: .whitespacesAndNewlines)
        var e = byKey[k] ?? (PayeeStat(id: k, payee: spelling, count: 0, total: 0), t.date)
        e.stat.count += 1
        e.stat.total += t.amount
        if t.date >= e.latest { e.latest = t.date; e.stat.payee = spelling }
        byKey[k] = e
    }
    return byKey.values.map(\.stat).sorted { ($0.total, $1.id) > ($1.total, $0.id) }
}

/// Category of the most recent transaction with that payee.
public func lastCategory(forPayee p: String, in d: FinanceData) -> UUID? {
    let k = normalizedPayee(p)
    return d.transactions.filter { payeeKey($0) == k }.max { $0.date < $1.date }?.categoryId
}

/// Distinct payees starting with `prefix`, most used first, in their most recent spelling.
public func payeeSuggestions(_ prefix: String, in d: FinanceData, limit: Int = 8) -> [String] {
    let pk = normalizedPayee(prefix)
    var byKey: [String: (count: Int, latest: Day, spelling: String)] = [:]
    for t in d.transactions {
        guard let k = payeeKey(t), k.hasPrefix(pk) else { continue }
        let spelling = t.payee!.trimmingCharacters(in: .whitespacesAndNewlines)
        var e = byKey[k] ?? (0, t.date, spelling)
        e.count += 1
        if t.date >= e.latest { e.latest = t.date; e.spelling = spelling }
        byKey[k] = e
    }
    return byKey.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.prefix(limit).map(\.value.spelling)
}

/// Running total of expenses for each day 1...min(through, days in month). Index 0 = day 1.
public func cumulativeSpending(_ d: FinanceData, _ m: YearMonth, through day: Int) -> [Decimal] {
    var perDay = [Decimal](repeating: 0, count: m.dayCount)
    for t in d.transactions where t.kind == .expense && m.contains(t.date) { perDay[t.date.day - 1] += t.amount }
    var out: [Decimal] = []
    var run: Decimal = 0
    for v in perDay.prefix(max(0, min(day, m.dayCount))) { run += v; out.append(run) }
    return out
}

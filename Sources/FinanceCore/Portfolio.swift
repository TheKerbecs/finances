import Foundation

public func roundTo(_ x: Decimal, _ places: Int) -> Decimal {
    var x = x, r = Decimal()
    NSDecimalRound(&r, &x, places, .plain)
    return r
}

public struct Position: Identifiable, Equatable, Sendable {
    public var id: UUID   // holdingId
    public var units: Decimal
    public var putIn: Decimal
    public var worth: Decimal?
    public var gain: Decimal?
    public var gainPercent: Decimal?
}

private func percent(_ gain: Decimal, of base: Decimal) -> Decimal? {
    base > 0 ? roundTo(gain / base * 100, 2) : nil
}

public func position(of h: Holding, trades: [Trade]) -> Position {
    var units: Decimal = 0, putIn: Decimal = 0
    for t in trades where t.holdingId == h.id {
        units += t.side == .buy ? t.units : -t.units
        putIn += t.side == .buy ? t.amount : -t.amount
    }
    let worth = h.lastPrice.map { units * $0 }
    let gain = worth.map { $0 - putIn }
    return Position(id: h.id, units: units, putIn: putIn, worth: worth, gain: gain,
                    gainPercent: gain.flatMap { percent($0, of: putIn) })
}

public struct Totals: Equatable, Sendable {
    public var putIn: Decimal, worth: Decimal, gain: Decimal
    public var gainPercent: Decimal?
}

/// A position without a price counts as worth what was put in, so it doesn't show as a loss.
public func totals(_ ps: [Position]) -> Totals {
    let putIn = ps.reduce(0) { $0 + $1.putIn }
    let worth = ps.reduce(0) { $0 + ($1.worth ?? $1.putIn) }
    return Totals(putIn: putIn, worth: worth, gain: worth - putIn, gainPercent: percent(worth - putIn, of: putIn))
}

public struct ValuePoint: Identifiable, Equatable, Sendable {
    public var id: Day { day }
    public var day: Day
    public var putIn: Decimal
    public var value: Decimal
}

/// One point per day from the first trade to `through`. Value uses the latest close on or before
/// each day, else the latest trade price, else 0.
public func valueSeries(holdings: [Holding], trades: [Trade], closes: [UUID: [Day: Decimal]], through: Day) -> [ValuePoint] {
    guard let first = trades.map(\.date).min(), first <= through else { return [] }
    struct State { var trades: [Trade]; var ti = 0; var units: Decimal = 0; var price: Decimal = 0 }
    var states: [UUID: State] = [:]
    for h in holdings {
        states[h.id] = State(trades: trades.filter { $0.holdingId == h.id }.sorted { $0.date < $1.date })
    }
    var putIn: Decimal = 0
    var out: [ValuePoint] = []
    var d = first
    while d <= through {
        var value: Decimal = 0
        for h in holdings {
            var s = states[h.id]!
            while s.ti < s.trades.count, s.trades[s.ti].date <= d {
                let t = s.trades[s.ti]
                s.units += t.side == .buy ? t.units : -t.units
                putIn += t.side == .buy ? t.amount : -t.amount
                if t.pricePerUnit > 0 { s.price = t.pricePerUnit }
                s.ti += 1
            }
            if let c = closes[h.id]?[d] { s.price = c }
            value += s.units * s.price
            states[h.id] = s
        }
        out.append(ValuePoint(day: d, putIn: putIn, value: value))
        d = d.adding(days: 1)
    }
    return out
}

/// Units of a holding held at the end of `day`, ignoring the trade `excluding` (the one being edited).
public func unitsHeld(_ holdingId: UUID, on day: Day, trades: [Trade], excluding: UUID? = nil) -> Decimal {
    trades.filter { $0.holdingId == holdingId && $0.date <= day && $0.id != excluding }
        .reduce(0) { $0 + ($1.side == .buy ? $1.units : -$1.units) }
}

import Foundation
import FinanceCore

func runPortfolioChecks() {
    var h = Holding(name: "X", ticker: "X.DE", lastPrice: 55)
    func tr(_ side: Side, _ amount: Decimal, _ units: Decimal, _ date: String = "2026-11-02", price: Decimal = 0) -> Trade {
        Trade(holdingId: h.id, date: day(date), side: side, amount: amount, units: units, pricePerUnit: price)
    }
    let p = position(of: h, trades: [tr(.buy, 100, 2), tr(.buy, 100, 1), tr(.sell, 60, 1)])
    precondition(p.id == h.id && p.units == 2 && p.putIn == 140 && p.worth == 110 && p.gain == -30 && p.gainPercent == dec("-21.43"))
    // other holdings' trades are ignored
    precondition(position(of: h, trades: [Trade(holdingId: UUID(), date: day("2026-11-02"), side: .buy, amount: 5, units: 5, pricePerUnit: 1)]).units == 0)

    h.lastPrice = 70
    let sold = position(of: h, trades: [tr(.buy, 100, 2), tr(.sell, 120, 2)])
    precondition(sold.units == 0 && sold.worth == 0 && sold.putIn == -20 && sold.gainPercent == nil)

    h.lastPrice = nil
    let noPrice = position(of: h, trades: [tr(.buy, 100, 2)])
    precondition(noPrice.worth == nil && noPrice.gain == nil && noPrice.gainPercent == nil)

    let t = totals([p, noPrice])
    precondition(t.putIn == 240 && t.worth == 210 && t.gain == -30 && t.gainPercent == dec("-12.5"))
    precondition(totals([]).gainPercent == nil)

    // series: buy 2u on 11-24 at 10, closes 11-24 = 10, 11-26 = 12, 11-25 missing
    let buy = tr(.buy, 20, 2, "2026-11-24", price: 10)
    let c: [Day: Decimal] = [day("2026-11-24"): 10, day("2026-11-26"): 12]
    let vs = valueSeries(holdings: [h], trades: [buy], closes: [h.id: c], through: day("2026-11-27"))
    precondition(vs.map(\.day.description) == ["2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27"])
    precondition(vs.map(\.value) == [20, 20, 24, 24] && vs.allSatisfy { $0.putIn == 20 })
    // no closes: falls back to trade price
    precondition(valueSeries(holdings: [h], trades: [buy], closes: [:], through: day("2026-11-25")).map(\.value) == [20, 20])
    precondition(valueSeries(holdings: [h], trades: [], closes: [:], through: day("2026-11-25")).isEmpty)
    precondition(roundTo(dec("3.3195020746"), 6) == dec("3.319502"))

    // units held on a date, optionally ignoring the trade being edited
    let b1 = tr(.buy, 100, 2, "2026-11-01"), b2 = tr(.buy, 100, 1, "2026-11-10"), s1 = tr(.sell, 60, 1, "2026-11-05")
    let all = [b1, b2, s1]
    precondition(unitsHeld(h.id, on: day("2026-11-05"), trades: all) == 1)
    precondition(unitsHeld(h.id, on: day("2026-11-30"), trades: all) == 2)
    precondition(unitsHeld(h.id, on: day("2026-11-30"), trades: all, excluding: s1.id) == 3)
    precondition(unitsHeld(h.id, on: day("2026-10-30"), trades: all) == 0)
}

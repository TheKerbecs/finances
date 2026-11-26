import SwiftUI
import FinanceCore

func euro(_ x: Decimal) -> String { x.formatted(.currency(code: "EUR")) }

func signedEuro(_ x: Decimal) -> String { (x > 0 ? "+" : "") + euro(x) }

func percent(_ x: Decimal?) -> String {
    guard let x else { return "–" }
    return (x > 0 ? "+" : "") + x.formatted(.number.precision(.fractionLength(2))) + "\u{00A0}%"
}

func units(_ x: Decimal) -> String { x.formatted(.number.precision(.fractionLength(0...6))) }

func plain(_ x: Decimal) -> String { x.formatted(.number.precision(.fractionLength(0...6)).grouping(.never)) }

func monthTitle(_ m: YearMonth) -> String {
    Day(year: m.year, month: m.month, day: 1).date().formatted(.dateTime.month(.wide).year())
}

/// "Nov 20" this year, "Nov 20, 2025" otherwise.
func dayText(_ d: Day) -> String {
    d.year == Day.today().year ? d.date().formatted(.dateTime.month(.abbreviated).day()) : d.date().formatted(date: .abbreviated, time: .omitted)
}

extension Binding where Value == Day {
    var asDate: Binding<Date> {
        Binding<Date>(get: { wrappedValue.date() }, set: { wrappedValue = Day($0) })
    }
}

/// In the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode. The property
/// wrapper type still exists; reaching it through a typealias skips the macro.
typealias Local = SwiftUI.State

/// SwiftUI has its own `Transaction`.
typealias Tx = FinanceCore.Transaction

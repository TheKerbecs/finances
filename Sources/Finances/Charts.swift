import SwiftUI
import Charts
import FinanceCore

/// Series colors (validated light + dark): In, Spent, Invested. Fixed order, never cycled.
enum SeriesColor {
    static let inflow = Theme.hex(0x338ced)
    static let spent = Theme.hex(0xe76624)
    static let invested = Theme.hex(0x00a888)
    /// Flexible (one-off) spending, next to `spent` for fixed costs.
    static let flexible = Theme.hex(0xd28e05)
    static let left = Theme.hex(0x8592A8)
}

func firstOfMonth(_ m: YearMonth) -> Date { Day(year: m.year, month: m.month, day: 1).date() }

/// The `n` months ending with `end`, oldest first.
func monthsEnding(_ end: YearMonth, count n: Int) -> [YearMonth] {
    var out = [end]
    while out.count < n { out.insert(out[0].previous, at: 0) }
    return out
}

/// Axis labels: whole euros, grouped ("12.000 €").
func euroShort(_ d: Double) -> String { d.formatted(.number.precision(.fractionLength(0))) + " €" }

extension View {
    func monthAxis() -> some View {
        chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true).foregroundStyle(Theme.tertiary)
        } }
    }
    func euroAxis() -> some View {
        chartYAxis {
            AxisMarks { (v: AxisValue) in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel { Text(euroShort(v.as(Double.self) ?? 0)).foregroundStyle(Theme.tertiary).frame(width: 62, alignment: .leading) }
            }
        }
    }
}

struct NoData: View {
    var text = "No data yet"
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity, minHeight: 140)
    }
}

/// Colored dot + label + value, for legends.
struct LegendItem: View {
    var color: Color
    var label: String
    var value: String
    var faded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(faded ? 0.45 : 1)).frame(width: 9, height: 9)
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).monospacedDigit()
        }
    }
}

/// Label above a value, no color key.
struct StatItem: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).monospacedDigit()
        }
    }
}

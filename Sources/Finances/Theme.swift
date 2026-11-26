import SwiftUI
import FinanceCore

/// Deep-navy finance look: navy canvas, bordered cards with large radii, one blue accent,
/// a validated 8-hue palette for categories.
enum Theme {
    static let bg = hex(0x0A101C)
    static let sidebar = hex(0x0C1321)
    static let card = hex(0x101827)
    static let raised = hex(0x172238)
    static let border = hex(0x1D2A42)
    static let text = hex(0xEDF1F7)
    static let secondary = hex(0x8592A8)
    static let tertiary = hex(0x56627A)
    static let accent = hex(0x5B8CFF)
    static let gain = hex(0x3DD68C)
    static let loss = hex(0xFF6B6B)

    static func gainColor(_ x: Decimal?) -> Color {
        guard let x, x != 0 else { return secondary }
        return x > 0 ? gain : loss
    }

    /// Category hues (dataviz palette, dark steps; validated on #101827). "Other" is grey.
    static let categoryHues: [Color] = [0x338ced, 0xe76624, 0x00a888, 0xd28e05, 0xe24d8b, 0x0aac23, 0x9887ef, 0xeb6263].map(hex)

    static func hex(_ v: UInt32) -> Color {
        Color(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

extension FinanceData {
    /// Color follows the category (its position in its kind's list), never its rank this month.
    func color(ofCategory id: UUID?) -> Color {
        guard let c = category(id) else { return Theme.tertiary }
        if c.name.lowercased() == "other" { return Theme.secondary }
        let list = categories.filter { $0.kind == c.kind && $0.name.lowercased() != "other" }
        let i = list.firstIndex { $0.id == c.id } ?? 0
        return Theme.categoryHues[i % Theme.categoryHues.count]
    }
}

/// An amount with the cents and currency set smaller: "965" + ",19 €".
struct Money: View {
    var amount: Decimal
    var size: CGFloat
    var weight: Font.Weight = .semibold
    var signed = false
    var color: Color = Theme.text

    var body: some View {
        let s = signed ? signedEuro(amount) : euro(amount)
        let sep = Locale.current.decimalSeparator ?? ","
        let parts = s.range(of: sep, options: .backwards).map { (String(s[..<$0.lowerBound]), String(s[$0.lowerBound...])) } ?? (s, "")
        (Text(parts.0).font(.system(size: size, weight: weight, design: .rounded))
            + Text(parts.1).font(.system(size: size * 0.55, weight: weight, design: .rounded)).foregroundColor(color.opacity(0.6)))
            .foregroundColor(color)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// Bordered card with a title and an optional link on the right.
struct Card<Content: View>: View {
    var title: String
    var link: String?
    var icon = "arrow.up.right"
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                if let link, let action {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            Text(link)
                            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }
}

/// "↗ 13,92 %" on a tinted pill.
struct ChangeBadge: View {
    var percent: Decimal?
    var value: Decimal?
    var body: some View {
        let up = (value ?? percent ?? 0) >= 0
        let c = Theme.gainColor(value ?? percent)
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10, weight: .bold))
            Text(percent.map { abs($0).formatted(.number.precision(.fractionLength(2))) + "\u{00A0}%" } ?? "–")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(c)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(c.opacity(0.15)))
    }
}

/// Segmented pills: 1M 3M 1Y All.
struct RangeChips<T: Hashable>: View {
    var options: [(String, T)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { o in
                Button { selection = o.1 } label: {
                    Text(o.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == o.1 ? Theme.text : Theme.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(selection == o.1 ? Theme.raised : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Category icon on a tinted rounded square in the category's color.
struct CategoryIcon: View {
    var name: String
    var kind: Kind = .expense
    var color: Color
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: Self.symbol(name, kind))
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.16)))
    }

    static func symbol(_ name: String, _ kind: Kind) -> String {
        switch name.lowercased() {
        case "rent", "miete": return "house.fill"
        case "groceries": return "cart.fill"
        case "eating out": return "fork.knife"
        case "transport": return "tram.fill"
        case "subscriptions": return "play.rectangle.fill"
        case "shopping": return "bag.fill"
        case "health": return "cross.case.fill"
        case "leisure": return "figure.walk"
        case "salary": return "briefcase.fill"
        case "transfers": return "arrow.left.arrow.right"
        case "dividends": return "chart.line.uptrend.xyaxis"
        default: return kind == .income ? "arrow.down.circle.fill" : "square.grid.2x2.fill"
        }
    }
}

/// Bar on a track, in a given color.
struct ProgressTrack: View {
    var fraction: Double
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule().fill(color).frame(width: max(4, g.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
    }
}

/// Hover tooltip for charts.
struct ChartTooltip: View {
    var title: String
    var rows: [(String, String, Color?)]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 6) {
                    if let c = r.2 { Circle().fill(c).frame(width: 7, height: 7) }
                    Text(r.0).foregroundStyle(Theme.secondary)
                    Spacer(minLength: 10)
                    Text(r.1).foregroundStyle(Theme.text).monospacedDigit()
                }
                .font(.system(size: 11))
            }
        }
        .padding(10)
        .frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }
}

func dbl(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

/// Page title with controls on the right.
struct PageHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
            Spacer()
            trailing
        }
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)))
            .contentShape(Rectangle())
    }
}

struct SecondaryButton: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? Theme.loss : Theme.text)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised.opacity(configuration.isPressed ? 0.7 : 1)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
    }
}

/// Small icon-only button for headers.
struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(SecondaryButton())
        .help(help)
    }
}

/// Label above a field.
struct Field<Content: View>: View {
    var label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            content
        }
    }
}

extension View {
    /// Raised rounded input look for TextFields and pickers.
    func inputStyle() -> some View {
        self.textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
    }

    /// Sheet chrome: card background, padding, fixed width.
    func sheetStyle(width: CGFloat = 460) -> some View {
        self.padding(24)
            .frame(width: width)
            .background(Theme.card)
            .presentationBackground(Theme.card)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
    }

    /// Row highlight on hover.
    func hoverRow(radius: CGFloat = 10) -> some View { modifier(HoverRow(radius: radius)) }
}

private struct HoverRow: ViewModifier {
    var radius: CGFloat
    @Local private var on = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(on ? Theme.raised.opacity(0.7) : .clear))
            .contentShape(Rectangle())
            .onHover { on = $0 }
    }
}

/// Menu that looks like an input and shows the category's icon.
struct CategoryMenu: View {
    @Environment(AppModel.self) private var model
    var kind: Kind
    @Binding var selection: UUID?
    var onPick: (() -> Void)?

    var body: some View {
        let c = model.data.category(selection)
        Menu {
            ForEach(model.categories(kind)) { cat in
                Button { selection = cat.id; onPick?() } label: { Label(cat.name, systemImage: CategoryIcon.symbol(cat.name, kind)) }
            }
        } label: {
            HStack(spacing: 8) {
                if let c { CategoryIcon(name: c.name, kind: kind, color: model.data.color(ofCategory: c.id), size: 17) }
                Text(c?.name ?? "Choose").foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .inputStyle()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

/// Generic menu with input look.
struct InputMenu<T: Hashable>: View {
    var options: [(String, T)]
    @Binding var selection: T
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { o in Button(o.0) { selection = o.1 } }
        } label: {
            HStack {
                Text(options.first { $0.1 == selection }?.0 ?? "Choose").foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
            }
            .inputStyle()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

/// Date picker in input look.
struct DateInput: View {
    @Binding var day: Day
    var body: some View {
        DatePicker("", selection: $day.asDate, displayedComponents: .date)
            .datePickerStyle(.field).labelsHidden()
            .inputStyle()
    }
}

/// Search box for headers.
struct SearchBox: View {
    @Binding var text: String
    var prompt: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.text)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border))
    }
}

/// Holding avatar: first letters on an aqua tint.
struct HoldingIcon: View {
    var name: String
    var size: CGFloat = 34
    var body: some View {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(letters.isEmpty ? "?" : letters.uppercased())
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(SeriesColor.invested)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(SeriesColor.invested.opacity(0.16)))
    }
}

/// "Repeats" choices for new entries; nil = one-off.
let repeatOptions: [(String, Frequency?)] = [("Never", nil), ("Weekly", .weekly), ("Monthly", .monthly), ("Every 3 months", .quarterly), ("Yearly", .yearly)]

/// Hint under a form with "Repeats" set; says how many entries saving adds right away.
func repeatHint(_ f: Frequency, start: Day) -> String {
    let due = occurrences(of: ruleForRepeat(f, date: start, amount: 1), through: .today()).count
    let now = due == 0 ? "The first one is added on \(dayText(start))." : due == 1 ? "The first one is added now." : "This adds \(due) past entries now."
    return "Saved as a recurring entry, \(frequencyText(f)) from \(dayText(start)). \(now) Change or stop it in Settings."
}

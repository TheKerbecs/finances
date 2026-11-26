import SwiftUI
import Charts
import FinanceCore

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Overview").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                    Spacer()
                    MonthSwitcher(month: $model.month)
                }
                .padding(.bottom, 4)
                Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                    GridRow {
                        MonthEndCard().gridCellColumns(2)
                    }
                    GridRow {
                        AccountsCard()
                        PortfolioCard()
                    }
                    GridRow {
                        SpendingCard()
                        CategoriesCard()
                    }
                    GridRow {
                        RecentCard().gridCellColumns(2)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }
}

/// ‹ November 2026 › on a raised pill.
struct MonthSwitcher: View {
    @Binding var month: YearMonth
    var body: some View {
        HStack(spacing: 8) {
            if month != Day.today().yearMonth {
                Button("This month") { month = Day.today().yearMonth }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 0) {
                Button { month = month.previous } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30).contentShape(Rectangle()) }
                    .keyboardShortcut("[", modifiers: .command)
                Text(monthTitle(month)).font(.system(size: 13, weight: .semibold)).frame(minWidth: 116)
                Button { month = month.next } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30).contentShape(Rectangle()) }
                    .keyboardShortcut("]", modifiers: .command)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .background(Capsule().fill(Theme.card))
            .overlay(Capsule().strokeBorder(Theme.border))
        }
    }
}

/// Spending so far against last month at the same day.
private struct SpendingCard: View {
    @Environment(AppModel.self) private var model
    @Local private var hover: Int?

    var body: some View {
        let m = model.month
        let s = monthSummary(model.data, m)
        let today = Day.today()
        let upTo = m == today.yearMonth ? today.day : (m < today.yearMonth ? m.dayCount : 0)
        let now = cumulativeSpending(model.data, m, through: upTo)
        let prev = cumulativeSpending(model.data, m.previous, through: 31)
        let prevName = monthTitle(m.previous).components(separatedBy: " ").first ?? ""
        let diff: Decimal? = now.last.flatMap { cur in prev.isEmpty ? nil : cur - prev[min(now.count, prev.count) - 1] }

        Card(title: "Spending so far", link: "Transactions", action: { model.section = .transactions }) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Money(amount: s.spent, size: 24)
                Text("spent in \(monthTitle(m).components(separatedBy: " ").first ?? "")").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Chart {
                ForEach(Array(prev.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Day", i + 1), y: .value("Euro", dbl(v)), series: .value("Month", "prev"))
                        .foregroundStyle(Theme.tertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
                ForEach(Array(now.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("Day", i + 1), y: .value("Euro", dbl(v)), series: .value("Month", "now"))
                        .foregroundStyle(SeriesColor.spent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = now.last {
                    PointMark(x: .value("Day", now.count), y: .value("Euro", dbl(last)))
                        .foregroundStyle(SeriesColor.spent).symbolSize(70)
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if let diff, hover == nil {
                                Text("\(euro(abs(diff))) \(diff > 0 ? "more" : "less") than \(prevName)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(diff > 0 ? Color.black : Theme.text)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(diff > 0 ? SeriesColor.spent : Theme.raised))
                            }
                        }
                }
                if let h = hover, h >= 1 {
                    RuleMark(x: .value("Day", h)).foregroundStyle(Theme.border)
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartTooltip(title: "Day \(h)", rows: [
                                (monthTitle(m).components(separatedBy: " ").first ?? "", h <= now.count ? euro(now[h - 1]) : "–", SeriesColor.spent),
                                (prevName, h <= prev.count ? euro(prev[h - 1]) : "–", Theme.tertiary)])
                        }
                }
            }
            .chartXScale(domain: 1...m.dayCount)
            .chartXAxis { AxisMarks(values: [1, 8, 15, 22, m.dayCount]) { _ in AxisValueLabel(collisionResolution: .disabled).foregroundStyle(Theme.tertiary) } }
            .chartYAxis(.hidden)
            .chartXSelection(value: $hover)
            .frame(height: 150)


        }
    }

}

/// Worth, gain badge, and worth vs. put in over a chosen range.
struct PortfolioCard: View {
    @Environment(AppModel.self) private var model
    var linkToInvestments = true
    @Local private var days = 90
    @Local private var hover: Date?

    var body: some View {
        let t = totals(model.positions())
        let today = Day.today()
        let series = valueSeries(holdings: model.data.holdings, trades: model.data.trades, closes: model.closes, through: today)
            .filter { days == 0 || $0.day >= today.adding(days: -days) }
        let selected = hover.flatMap { h in series.min { abs($0.day.date().timeIntervalSince(h)) < abs($1.day.date().timeIntervalSince(h)) } }

        Card(title: "Portfolio", link: linkToInvestments ? "Investments" : nil, action: { model.section = .investments }) {
            if model.data.holdings.isEmpty {
                Text("Add your ETFs and stocks under Investments to see what they're worth.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Money(amount: t.worth, size: 30)
                    ChangeBadge(percent: t.gainPercent, value: t.gain)
                }
                Text("\(signedEuro(t.gain)) on \(euro(t.putIn)) put in").font(.system(size: 13)).foregroundStyle(Theme.secondary).monospacedDigit()
                if series.count > 1 {
                    Chart {
                        ForEach(series) { p in
                            LineMark(x: .value("Day", p.day.date()), y: .value("Euro", dbl(p.putIn)), series: .value("S", "put"))
                                .foregroundStyle(Theme.tertiary)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                                .interpolationMethod(.stepEnd)
                            LineMark(x: .value("Day", p.day.date()), y: .value("Euro", dbl(p.value)), series: .value("S", "worth"))
                                .foregroundStyle(SeriesColor.invested)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        if let last = series.last, selected == nil {
                            PointMark(x: .value("Day", last.day.date()), y: .value("Euro", dbl(last.value)))
                                .foregroundStyle(SeriesColor.invested).symbolSize(70)
                        }
                        if let s = selected {
                            RuleMark(x: .value("Day", s.day.date())).foregroundStyle(Theme.border)
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    ChartTooltip(title: dayText(s.day), rows: [
                                        ("Worth", euro(roundTo(s.value, 2)), SeriesColor.invested),
                                        ("Put in", euro(s.putIn), Theme.tertiary)])
                                }
                            PointMark(x: .value("Day", s.day.date()), y: .value("Euro", dbl(s.value)))
                                .foregroundStyle(SeriesColor.invested).symbolSize(60)
                        }
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXSelection(value: $hover)
                    .frame(height: 124)
                }
                RangeChips(options: [("1M", 30), ("3M", 90), ("1Y", 365), ("All", 0)], selection: $days)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Latest entries of the month, grouped by day.
private struct RecentCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let m = model.month
        let recent = Array(model.data.transactions.filter { m.contains($0.date) }.sorted { $0.date > $1.date }.prefix(8))
        let days = recent.reduce(into: [Day]()) { if $0.last != $1.date { $0.append($1.date) } }

        Card(title: "Latest entries", link: "View all", action: { model.filter.categoryId = nil; model.section = .transactions }) {
            if recent.isEmpty {
                Text("Nothing in \(monthTitle(m)) yet. Press ⌘N to add an entry.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(days, id: \.self) { d in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayHeading(d)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        ForEach(recent.filter { $0.date == d }) { t in row(t) }
                    }
                }
            }
        }
    }

    private func row(_ t: Tx) -> some View {
        let c = model.data.category(t.categoryId)
        return HStack(spacing: 12) {
            CategoryIcon(name: c?.name ?? "", kind: t.kind, color: model.data.color(ofCategory: t.categoryId), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(t.payee ?? c?.name ?? "–").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if t.recurringId != nil { Image(systemName: "repeat").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary) }
                }
                Text([c?.name, t.note].compactMap { $0 }.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(t.kind == .income ? "+" + euro(t.amount) : "−" + euro(t.amount))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(t.kind == .income ? Theme.gain : Theme.text)
        }
    }
}

func dayHeading(_ d: Day) -> String {
    let today = Day.today()
    if d == today { return "Today" }
    if d == today.adding(days: -1) { return "Yesterday" }
    return d.date().formatted(.dateTime.weekday(.wide).day().month(.wide))
}

/// Spending per category this month, with how often.
private struct CategoriesCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = categoryStats(model.data, model.month, kind: .expense)
        let top = stats.first?.total ?? 1
        Card(title: "Top categories", link: "Analytics", action: { model.section = .analytics }) {
            if stats.isEmpty { Text("No spending this month.").font(.system(size: 13)).foregroundStyle(Theme.secondary) }
            VStack(spacing: 16) {
                ForEach(stats.prefix(7)) { s in
                    let color = model.data.color(ofCategory: s.id)
                    Button {
                        model.filter.categoryId = s.id
                        model.section = .transactions
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(name: s.name, color: color, size: 30)
                            VStack(spacing: 7) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(s.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                    Text("\(s.count)×").font(.system(size: 12)).foregroundStyle(Theme.tertiary).monospacedDigit()
                                    Spacer()
                                    Text(euro(s.total)).font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.text).monospacedDigit()
                                }
                                ProgressTrack(fraction: top > 0 ? dbl(s.total / top) : 0, color: color)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show these entries")
                }
            }
        }
    }
}

/// What will be left at the end of the month: recorded entries plus recurring ones still to come.
private struct MonthEndCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let m = model.month
        let today = Day.today()
        let f = forecast(model.data, m, today: today)
        let monthName = monthTitle(m).components(separatedBy: " ").first ?? ""
        let past = m < today.yearMonth
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(past ? "Left at the end of \(monthName)" : "Left at the end of \(monthName), as planned")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Money(amount: abs(f.left), size: 44, color: f.left < 0 ? Theme.loss : Theme.text)
                        if f.left < 0 { Text("short").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.loss) }
                    }
                    Text(f.income > 0 ? "out of \(euro(f.income)) income" : "No income recorded or scheduled for \(monthName) yet.")
                        .font(.system(size: 13)).foregroundStyle(Theme.secondary).monospacedDigit()
                }
                Spacer()
                if let perDay = f.perDay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Free to spend").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        Text("\(euro(perDay)) a day").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).monospacedDigit()
                        Text("for the next \(f.daysRemaining) \(f.daysRemaining == 1 ? "day" : "days")").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
                }
            }

            if f.income > 0 || f.fixed + f.spentFlexible + f.investing > 0 { bar(f) }

            HStack(alignment: .top, spacing: 0) {
                LegendItem(color: SeriesColor.spent, label: "Fixed costs", value: euro(f.fixed)).frame(maxWidth: .infinity, alignment: .leading)
                LegendItem(color: SeriesColor.flexible, label: "Flexible spending", value: euro(f.spentFlexible)).frame(maxWidth: .infinity, alignment: .leading)
                LegendItem(color: SeriesColor.invested, label: "Invested", value: euro(f.investing)).frame(maxWidth: .infinity, alignment: .leading)
                LegendItem(color: SeriesColor.left, label: "Left", value: euro(f.left)).frame(maxWidth: .infinity, alignment: .leading)
            }

            if !f.upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Still coming in \(monthName)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(f.upcoming.prefix(6)) { u in upcomingRow(u) }
                    }
                    if f.upcoming.count > 6 {
                        Text("and \(f.upcoming.count - 6) more").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                }
            } else if f.income == 0 {
                Button { model.section = .settings } label: { Label("Add your salary as a recurring entry", systemImage: "plus") }
                    .buttonStyle(SecondaryButton())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
    }

    /// Income split into fixed / flexible / invested / left. Parts still to come are lighter.
    private func bar(_ f: MonthForecast) -> some View {
        let total = max(f.income, f.fixed + f.spentFlexible + f.investing)
        let parts: [(Decimal, Color, Bool)] = [
            (f.spentFixed, SeriesColor.spent, false), (f.scheduledBills, SeriesColor.spent, true),
            (f.spentFlexible, SeriesColor.flexible, false),
            (f.invested, SeriesColor.invested, false), (f.plannedInvesting, SeriesColor.invested, true),
            (max(f.left, 0), SeriesColor.left.opacity(0.35), false),
        ].filter { $0.0 > 0 }
        return GeometryReader { g in
            HStack(spacing: 3) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(p.1.opacity(p.2 ? 0.4 : 1))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(p.1, style: StrokeStyle(lineWidth: p.2 ? 1 : 0, dash: [3, 2])))
                        .frame(width: max(4, (g.size.width - CGFloat(parts.count - 1) * 3) * CGFloat(dbl(p.0 / total))))
                }
            }
        }
        .frame(height: 14)
        .help("Lighter parts are recurring entries still to come")
    }

    private func upcomingRow(_ u: Upcoming) -> some View {
        HStack(spacing: 10) {
            if u.kind == .investment {
                HoldingIcon(name: u.title, size: 26)
            } else if u.kind == .transfer {
                TransferIcon(size: 26)
            } else {
                CategoryIcon(name: model.data.category(u.categoryId)?.name ?? "", kind: u.kind == .income ? .income : .expense,
                             color: model.data.color(ofCategory: u.categoryId), size: 26)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(u.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text(u.date.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 6)
            Text((u.kind == .income ? "+" : u.kind == .transfer ? "" : "−") + euro(u.amount))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(u.kind == .income ? Theme.gain : u.kind == .investment ? SeriesColor.invested : u.kind == .transfer ? Theme.secondary : Theme.text)
        }
    }
}

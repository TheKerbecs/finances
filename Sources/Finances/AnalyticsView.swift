import SwiftUI
import Charts
import FinanceCore

/// The months the Analytics page looks at: 1, 3 or 12 ending with the selected month.
struct Period: Equatable {
    var end: YearMonth
    var length: Int
    var months: [YearMonth] { monthsEnding(end, count: length) }
    var start: YearMonth { months[0] }
    var title: String {
        length == 1 ? monthTitle(end) : "\(monthTitle(start).components(separatedBy: " ").first ?? "") – \(monthTitle(end))"
    }
    var firstDay: Day { Day(year: start.year, month: start.month, day: 1) }
    var lastDay: Day { Day(year: end.year, month: end.month, day: end.dayCount) }
}

struct AnalyticsView: View {
    @Environment(AppModel.self) private var model
    @Local private var length = 1

    var body: some View {
        @Bindable var model = model
        let period = Period(end: model.month, length: length)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Analytics") {
                    RangeChips(options: [("Month", 1), ("3 months", 3), ("Year", 12)], selection: $length)
                    MonthSwitcher(month: $model.month)
                }
                if length > 1 {
                    Text(period.title).font(.system(size: 13)).foregroundStyle(Theme.secondary).padding(.top, -10)
                }
                Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                    GridRow {
                        CashFlowCard(period: period)
                        WhereItGoesCard(period: period)
                    }
                    GridRow {
                        FixedCostsCard()
                        HowOftenCard(period: period)
                    }
                    GridRow {
                        OverTimeCard(end: model.month).gridCellColumns(2)
                    }
                    GridRow {
                        CategoryDetailCard(period: period)
                        PortfolioHistoryCard()
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
            Color.clear.frame(height: 1).id("bottom")
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["FINANCES_SNAPSHOT_BOTTOM"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        }
        .background(Theme.bg)
    }
}

// MARK: - Cash flow

/// Income → fixed → flexible → invested → left, as floating bars. Includes what's still
/// scheduled when the period reaches into the current or a future month.
private struct CashFlowCard: View {
    @Environment(AppModel.self) private var model
    var period: Period

    struct Step: Identifiable {
        var id: String { label }
        var label: String, start: Double, end: Double, value: Decimal, color: Color
    }

    var body: some View {
        let today = Day.today()
        var c = cashFlow(model.data, from: period.start, to: period.end)
        var scheduled = 0
        for m in period.months where m >= today.yearMonth {
            let f = forecast(model.data, m, today: today)
            c.income += f.expectedIncome; c.fixed += f.scheduledBills; c.invested += f.plannedInvesting
            scheduled += f.upcoming.count
        }
        let steps = makeSteps(c)
        return Card(title: "Cash flow") {
            if c.income == 0 && c.fixed + c.flexible + c.invested == 0 {
                NoData(text: "Nothing recorded for \(period.title).")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Money(amount: abs(c.left), size: 28, color: c.left < 0 ? Theme.loss : Theme.text)
                    Text(c.left < 0 ? "more out than in" : "left over").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
                    if c.income > 0 {
                        Text("\(percent(roundTo(c.left / c.income * 100, 1)).replacingOccurrences(of: "+", with: "")) of income")
                            .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                    }
                }
                Chart(steps) { s in
                    BarMark(x: .value("Step", s.label), yStart: .value("From", s.start), yEnd: .value("To", s.end), width: .ratio(0.55))
                        .foregroundStyle(s.color)
                        .cornerRadius(4)
                        .annotation(position: .top, spacing: 4) {
                            Text(euro(s.value)).font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text).monospacedDigit()
                        }
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.secondary) } }
                .euroAxis()
                .frame(height: 220)
                if scheduled > 0 {
                    Text("Includes \(scheduled) recurring \(scheduled == 1 ? "entry" : "entries") still to come.")
                        .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
            }
        }
    }

    private func makeSteps(_ c: CashFlow) -> [Step] {
        let i = dbl(c.income), f = dbl(c.fixed), x = dbl(c.flexible), l = dbl(c.left)
        return [
            Step(label: "Income", start: 0, end: i, value: c.income, color: SeriesColor.inflow),
            Step(label: "Fixed", start: i, end: i - f, value: c.fixed, color: SeriesColor.spent),
            Step(label: "Flexible", start: i - f, end: i - f - x, value: c.flexible, color: SeriesColor.flexible),
            Step(label: "Invested", start: i - f - x, end: l, value: c.invested, color: SeriesColor.invested),
            Step(label: "Left", start: 0, end: l, value: c.left, color: l < 0 ? Theme.loss : SeriesColor.left),
        ]
    }
}

// MARK: - Where it goes

private struct WhereItGoesCard: View {
    @Environment(AppModel.self) private var model
    var period: Period
    @Local private var picked: Double?

    var body: some View {
        let stats = categoryStats(model.data, from: period.start, to: period.end, kind: .expense)
        let total = stats.reduce(Decimal(0)) { $0 + $1.total }
        let hovered = hoveredCategory(stats)
        return Card(title: "Where it goes") {
            if stats.isEmpty { NoData(text: "No spending in \(period.title).") } else {
                HStack(alignment: .top, spacing: 20) {
                    Chart(stats) { s in
                        SectorMark(angle: .value("Spent", dbl(s.total)), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .cornerRadius(4)
                            .foregroundStyle(model.data.color(ofCategory: s.id))
                            .opacity(hovered == nil || hovered?.id == s.id ? 1 : 0.35)
                    }
                    .chartAngleSelection(value: $picked)
                    .chartBackground { _ in
                        VStack(spacing: 2) {
                            Text(hovered?.name ?? "Spent").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            Text(euro(hovered?.total ?? total)).font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text).monospacedDigit()
                            if let h = hovered { Text("\(h.count)×").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .frame(width: 170, height: 170)

                    VStack(spacing: 9) {
                        ForEach(stats.prefix(8)) { s in row(s, total: total) }
                    }
                    .frame(minWidth: 200)
                }
            }
        }
    }

    private func hoveredCategory(_ stats: [CategoryStat]) -> CategoryStat? {
        guard let picked else { return nil }
        var run = 0.0
        for s in stats {
            run += dbl(s.total)
            if picked <= run { return s }
        }
        return nil
    }

    private func row(_ s: CategoryStat, total: Decimal) -> some View {
        let share = total > 0 ? NSDecimalNumber(decimal: roundTo(s.total / total * 100, 0)).intValue : 0
        return HStack(spacing: 10) {
            CategoryIcon(name: s.name, color: model.data.color(ofCategory: s.id), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(s.count)×, \(share) %").font(.system(size: 11)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(euro(s.total)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).monospacedDigit()
                comparison(s)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.filter.categoryId = s.id; model.section = .transactions }
        .help("Show these entries")
    }

    /// Month view: change against the 6 months before. Longer periods: average per month.
    @ViewBuilder private func comparison(_ s: CategoryStat) -> some View {
        if period.length == 1 {
            let avg = averagePerMonth(model.data, categoryId: s.id, before: period.end, months: 6)
            if avg > 0 {
                let change = roundTo((s.total - avg) / avg * 100, 0)
                Text((change > 0 ? "+" : "") + "\(NSDecimalNumber(decimal: change).intValue) % vs ⌀")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit().fixedSize()
                    .foregroundStyle(change > 10 ? Theme.loss : change < -10 ? Theme.gain : Theme.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.raised))
                    .help("Compared with your average of \(euro(avg)) a month over the 6 months before")
            }
        } else {
            Text("⌀ \(euro(roundTo(s.total / Decimal(period.length), 2)))").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                .monospacedDigit().help("Average per month")
        }
    }
}

// MARK: - Fixed costs

private struct FixedCostsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let costs = fixedCosts(model.data, today: .today())
        let perMonth = costs.reduce(Decimal(0)) { $0 + $1.perMonth }
        let perYear = costs.reduce(Decimal(0)) { $0 + $1.perYear }
        let income = forecast(model.data, Day.today().yearMonth, today: .today()).income
        return Card(title: "Fixed costs", link: "Edit", icon: "slider.horizontal.3", action: { model.section = .settings }) {
            if costs.isEmpty {
                NoData(text: "Add rent, subscriptions and other regular bills as recurring entries in Settings.")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Money(amount: perMonth, size: 28)
                    Text("a month").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(euro(perYear)) a year").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).monospacedDigit()
                        if income > 0 {
                            Text("\(NSDecimalNumber(decimal: roundTo(perMonth / income * 100, 0)).intValue) % of this month's income")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                VStack(spacing: 2) {
                    ForEach(costs.sorted { $0.perMonth > $1.perMonth }) { c in
                        HStack(spacing: 10) {
                            CategoryIcon(name: model.data.category(c.categoryId)?.name ?? "", color: model.data.color(ofCategory: c.categoryId), size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(euro(c.amount)) \(frequencyText(c.frequency))").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(euro(c.perMonth))/month").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                                Text("\(euro(c.perYear))/year").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                            .monospacedDigit()
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }
}

func frequencyText(_ f: Frequency) -> String {
    switch f {
    case .weekly: return "every week"
    case .monthly: return "every month"
    case .quarterly: return "every 3 months"
    case .yearly: return "every year"
    }
}

// MARK: - How often

/// Calendar heatmap of daily spending (weeks × weekdays) and spending by weekday.
private struct HowOftenCard: View {
    @Environment(AppModel.self) private var model
    var period: Period

    var body: some View {
        let daily = dailySpending(model.data, from: period.firstDay, to: period.lastDay, includeRecurring: false)
        let entries = model.data.transactions.filter { $0.kind == .expense && $0.recurringId == nil && $0.date >= period.firstDay && $0.date <= period.lastDay }
        let days = max(1, dayCount(period))
        let byWeekday = (1...7).map { w in daily.filter { $0.key.weekday == w }.reduce(Decimal(0)) { $0 + $1.value } }
        let topDay = byWeekday.enumerated().max { $0.element < $1.element }
        let names = ["Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays", "Sundays"]
        return Card(title: "How often") {
            if entries.isEmpty { NoData(text: "No one-off spending in \(period.title).") } else {
                Text("One-off spending, without rent and other recurring costs.").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                HStack(spacing: 28) {
                    StatItem(label: "Purchases", value: "\(entries.count)")
                    StatItem(label: "Per day", value: (Double(entries.count) / Double(days)).formatted(.number.precision(.fractionLength(1))))
                    StatItem(label: "Days without spending", value: "\(max(0, days - daily.filter { $0.key <= Day.today() }.count))")
                }
                Heatmap(period: period, daily: daily)
                if let top = topDay, top.element > 0 {
                    Text("You spend most on \(names[top.offset]).").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Chart(Array(byWeekday.enumerated()), id: \.offset) { i, v in
                    BarMark(x: .value("Day", String(names[i].prefix(3))), y: .value("Spent", dbl(v)), width: .ratio(0.5))
                        .foregroundStyle(i == topDay?.offset ? SeriesColor.spent : SeriesColor.spent.opacity(0.45))
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.secondary) } }
                .chartYAxis(.hidden)
                .frame(height: 70)
            }
        }
    }

    private func dayCount(_ p: Period) -> Int {
        let end = min(p.lastDay, Day.today())
        guard end >= p.firstDay else { return 0 }
        var n = 0, d = p.firstDay
        while d <= end { n += 1; d = d.adding(days: 1) }
        return n
    }
}

private struct Heatmap: View {
    var period: Period
    var daily: [Day: Decimal]

    var body: some View {
        // Columns are weeks starting Monday; rows are Monday…Sunday.
        let start = period.firstDay.adding(days: -(period.firstDay.weekday - 1))
        var weeks: [[Day]] = []
        var d = start
        while d <= period.lastDay {
            weeks.append((0..<7).map { d.adding(days: $0) })
            d = d.adding(days: 7)
        }
        let maxValue = daily.values.max() ?? 1
        let cell: CGFloat = period.length == 1 ? 26 : period.length == 3 ? 15 : 9
        let gap: CGFloat = period.length == 12 ? 2 : 3
        return HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .trailing, spacing: gap) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, l in
                    Text(l).font(.system(size: min(10, cell * 0.7))).foregroundStyle(Theme.tertiary).frame(height: cell)
                }
            }
            ForEach(weeks, id: \.first) { week in
                VStack(spacing: gap) {
                    ForEach(week, id: \.self) { day in
                        let inside = day >= period.firstDay && day <= period.lastDay
                        let v = daily[day] ?? 0
                        RoundedRectangle(cornerRadius: cell > 12 ? 5 : 2)
                            .fill(inside ? color(v, maxValue) : .clear)
                            .frame(width: cell, height: cell)
                            .overlay {
                                if period.length == 1, inside {
                                    Text("\(day.day)").font(.system(size: 9)).foregroundStyle(v > 0 ? Theme.text : Theme.tertiary)
                                }
                            }
                            .help(inside ? "\(dayText(day)): \(v > 0 ? euro(v) : "nothing spent")" : "")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One hue, five steps by share of the busiest day.
    private func color(_ v: Decimal, _ maxValue: Decimal) -> Color {
        guard v > 0, maxValue > 0 else { return Theme.raised }
        let r = dbl(v / maxValue)
        let step = r > 0.75 ? 1.0 : r > 0.5 ? 0.75 : r > 0.25 ? 0.55 : r > 0.1 ? 0.38 : 0.24
        return SeriesColor.spent.opacity(step)
    }
}

// MARK: - Over time

/// 12 months of in / spent / invested, and the savings rate underneath.
private struct OverTimeCard: View {
    @Environment(AppModel.self) private var model
    var end: YearMonth
    @Local private var hover: Date?

    struct Point: Identifiable { var id: String { "\(series)\(month)" }; var month: Date; var series: String; var value: Double }

    var body: some View {
        let months = monthsEnding(end, count: 12)
        let sums = months.map { (firstOfMonth($0), monthSummary(model.data, $0)) }
        let points = sums.flatMap { d, s in
            [Point(month: d, series: "In", value: dbl(s.income)), Point(month: d, series: "Spent", value: dbl(s.spent)),
             Point(month: d, series: "Invested", value: dbl(s.invested))]
        }
        let rates = sums.compactMap { d, s in savingsRate(s).map { (d, dbl($0)) } }
        let selected = hover.flatMap { h in sums.min { abs($0.0.timeIntervalSince(h)) < abs($1.0.timeIntervalSince(h)) } }
        let domain = firstOfMonth(months[0])...firstOfMonth(end.next)
        let avgRate = rates.isEmpty ? nil : rates.map(\.1).reduce(0, +) / Double(rates.count)
        return Card(title: "Over time") {
            if points.allSatisfy({ $0.value == 0 }) { NoData() } else {
                Chart {
                    ForEach(points) { p in bar(p, dim: selected != nil && selected?.0 != p.month) }
                    if let selected { tooltip(selected.0, selected.1) }
                }
                .chartForegroundStyleScale(["In": SeriesColor.inflow, "Spent": SeriesColor.spent, "Invested": SeriesColor.invested])
                .chartXScale(domain: domain)
                .monthAxis()
                .euroAxis()
                .chartLegend(position: .top, alignment: .leading)
                .chartXSelection(value: $hover)
                .frame(height: 230)

                HStack(alignment: .firstTextBaseline) {
                    Text("Savings rate").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if let last = rates.last, let avgRate {
                        Text("\(Int(last.1.rounded())) % in \(monthTitle(Day(last.0).yearMonth)), ⌀ \(Int(avgRate.rounded())) %")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.top, 4)
                if rates.isEmpty {
                    Text("Appears once income is recorded.").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                } else {
                    Chart {
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.border)
                        ForEach(rates, id: \.0) { d, r in
                            LineMark(x: .value("Month", d, unit: .month), y: .value("Rate", r))
                                .foregroundStyle(SeriesColor.invested).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                            PointMark(x: .value("Month", d, unit: .month), y: .value("Rate", r))
                                .foregroundStyle(SeriesColor.invested).symbolSize(30)
                        }
                        if let avgRate {
                            RuleMark(y: .value("Average", avgRate)).foregroundStyle(Theme.tertiary)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                    .chartXScale(domain: domain)
                    .monthAxis()
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: 2)) { (v: AxisValue) in
                            AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0)) %").foregroundStyle(Theme.tertiary).frame(width: 62, alignment: .leading) }
                        }
                    }
                    .frame(height: 90)
                }
            }
        }
    }

    @ChartContentBuilder private func bar(_ p: Point, dim: Bool) -> some ChartContent {
        BarMark(x: .value("Month", p.month, unit: .month), y: .value("Euro", p.value), width: .ratio(0.8))
            .position(by: .value("Series", p.series), axis: .horizontal)
            .foregroundStyle(by: .value("Series", p.series))
            .cornerRadius(4)
            .opacity(dim ? 0.4 : 1)
    }

    @ChartContentBuilder private func tooltip(_ month: Date, _ s: MonthSummary) -> some ChartContent {
        RuleMark(x: .value("Month", month, unit: .month))
            .foregroundStyle(.clear)
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                ChartTooltip(title: monthTitle(Day(month).yearMonth), rows: [
                    ("In", euro(s.income), SeriesColor.inflow),
                    ("Spent", euro(s.spent), SeriesColor.spent),
                    ("Invested", euro(s.invested), SeriesColor.invested),
                    ("Left", euro(s.left), nil),
                    ("Savings rate", savingsRate(s).map { "\($0) %" } ?? "–", nil)])
            }
    }
}

// MARK: - Category detail

private struct CategoryDetailCard: View {
    @Environment(AppModel.self) private var model
    var period: Period
    @Local private var categoryId: UUID?
    @Local private var hover: Date?

    var body: some View {
        let cid = categoryId ?? categoryStats(model.data, from: period.start, to: period.end, kind: .expense).first?.id
            ?? model.categories(.expense).first?.id
        let months = monthsEnding(period.end, count: 12)
        let rows = months.map { m in (firstOfMonth(m), categoryStats(model.data, m, kind: .expense).first { $0.id == cid }) }
        let total = rows.compactMap(\.1).reduce(Decimal(0)) { $0 + $1.total }
        let count = rows.compactMap(\.1).reduce(0) { $0 + $1.count }
        let avg = dbl(total / 12)
        let color = model.data.color(ofCategory: cid)
        let payees = payeeStats(model.data, nil).isEmpty ? [] : topPayees(cid)
        let selected = hover.flatMap { h in rows.map(\.0).min { abs($0.timeIntervalSince(h)) < abs($1.timeIntervalSince(h)) } }

        return Card(title: "Category detail") {
            CategoryMenu(kind: .expense, selection: Binding(get: { cid }, set: { categoryId = $0 })).frame(width: 230)
            if count == 0 { NoData(text: "Nothing in this category in the last 12 months.") } else {
                Text("\(count)× in 12 months, \(euro(total)) in total, ⌀ \(euro(total / 12)) a month")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
                Chart {
                    ForEach(rows, id: \.0) { d, s in
                        BarMark(x: .value("Month", d, unit: .month), y: .value("Euro", dbl(s?.total ?? 0)), width: .fixed(14))
                            .foregroundStyle(color.opacity(selected == nil || selected == d ? 1 : 0.4))
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(Theme.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("⌀").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                        }
                    if let selected, let r = rows.first(where: { $0.0 == selected }) {
                        RuleMark(x: .value("Month", selected, unit: .month)).foregroundStyle(.clear)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartTooltip(title: monthTitle(Day(selected).yearMonth), rows: [
                                    ("Spent", euro(r.1?.total ?? 0), color), ("Times", "\(r.1?.count ?? 0)×", nil)])
                            }
                    }
                }
                .monthAxis()
                .euroAxis()
                .chartXSelection(value: $hover)
                .frame(height: 180)
                if !payees.isEmpty {
                    Text("Top payees").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                    ForEach(payees.prefix(4)) { p in
                        HStack {
                            Text(p.payee).font(.system(size: 12)).foregroundStyle(Theme.text)
                            Spacer()
                            Text("\(p.count)×").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            Text(euro(p.total)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    private func topPayees(_ cid: UUID?) -> [PayeeStat] {
        var d = model.data
        let from = monthsEnding(period.end, count: 12)[0]
        d.transactions = d.transactions.filter { $0.categoryId == cid && $0.date.yearMonth >= from && $0.date.yearMonth <= period.end }
        return payeeStats(d, nil)
    }
}

// MARK: - Portfolio

private struct PortfolioHistoryCard: View {
    @Environment(AppModel.self) private var model
    @Local private var years = 1
    @Local private var hover: Date?

    var body: some View {
        let today = Day.today()
        let all = valueSeries(holdings: model.data.holdings, trades: model.data.trades, closes: model.closes, through: today)
        let shown = all.filter { years == 0 || $0.day >= today.adding(days: -365 * years) }
        let step = max(1, shown.count / 300)   // about 300 points is plenty at this width
        let sampled = shown.enumerated().filter { $0.offset % step == 0 || $0.offset == shown.count - 1 }.map(\.element)
        let selected = hover.flatMap { h in sampled.min { abs($0.day.date().timeIntervalSince(h)) < abs($1.day.date().timeIntervalSince(h)) } }
        return Card(title: "Portfolio", link: "Investments", action: { model.section = .investments }) {
            RangeChips(options: [("1Y", 1), ("3Y", 3), ("All", 0)], selection: $years)
            if sampled.count < 2 { NoData(text: "Add holdings and trades to see this.") } else {
                Chart {
                    ForEach(sampled) { p in
                        LineMark(x: .value("Date", p.day.date()), y: .value("Euro", dbl(p.putIn)), series: .value("S", "Put in"))
                            .foregroundStyle(Theme.tertiary).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                            .interpolationMethod(.stepEnd)
                        LineMark(x: .value("Date", p.day.date()), y: .value("Euro", dbl(p.value)), series: .value("S", "Worth"))
                            .foregroundStyle(SeriesColor.invested).lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    if let s = selected {
                        RuleMark(x: .value("Date", s.day.date())).foregroundStyle(Theme.border)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartTooltip(title: dayText(s.day), rows: [
                                    ("Worth", euro(roundTo(s.value, 2)), SeriesColor.invested),
                                    ("Put in", euro(s.putIn), Theme.tertiary),
                                    ("Gain", signedEuro(roundTo(s.value - s.putIn, 2)), nil)])
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .euroAxis()
                .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.tertiary) } }
                .chartXSelection(value: $hover)
                .frame(height: 220)
                HStack(spacing: 20) {
                    LegendItem(color: SeriesColor.invested, label: "Worth", value: euro(roundTo(sampled.last!.value, 2)))
                    LegendItem(color: Theme.tertiary, label: "Put in", value: euro(sampled.last!.putIn))
                }
            }
        }
    }
}

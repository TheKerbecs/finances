import SwiftUI
import FinanceCore

/// Custom sidebar: navigation with a filled pill for the current page, then holdings with their worth.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let thisMonth = model.data.transactions.filter { Day.today().yearMonth.contains($0.date) }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                    Text("Finances").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 10).padding(.bottom, 18)

                Button { model.showQuickAdd = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        Text("New entry").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("⌘N").font(.system(size: 11, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)

                item(.overview, "Overview", "square.grid.2x2")
                item(.transactions, "Transactions", "list.bullet.rectangle", badge: thisMonth > 0 ? "\(thisMonth)" : nil)
                item(.investments, "Investments", "chart.line.uptrend.xyaxis")
                item(.analytics, "Analytics", "chart.pie")
                item(.settings, "Settings", "gearshape")

                if !model.data.holdings.isEmpty {
                    Text("Holdings").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 10).padding(.top, 26).padding(.bottom, 6)
                    ForEach(model.positions()) { p in
                        if let h = model.data.holding(p.id) {
                            Button { model.section = .investments } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(SeriesColor.invested).frame(width: 7, height: 7)
                                    Text(h.name).lineLimit(1).foregroundStyle(Theme.text.opacity(0.85))
                                    Spacer(minLength: 6)
                                    Text(p.worth.map { $0.formatted(.number.precision(.fractionLength(0))) + " €" } ?? "–")
                                        .foregroundStyle(Theme.secondary).monospacedDigit()
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 44)
        }
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }

    private func item(_ s: Section, _ title: String, _ icon: String, badge: String? = nil) -> some View {
        let on = model.section == s
        return Button { model.section = s } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: on ? .semibold : .medium)).lineLimit(1).fixedSize()
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 11, weight: .semibold)).monospacedDigit().fixedSize()
                        .foregroundStyle(on ? Theme.text : Theme.secondary)
                }
            }
            .foregroundStyle(on ? Theme.text : Theme.secondary)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Theme.raised : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

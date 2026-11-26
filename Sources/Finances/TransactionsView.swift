import SwiftUI
import FinanceCore

struct TransactionsView: View {
    @Environment(AppModel.self) private var model
    @Local private var allMonths = false
    @Local private var kindFilter: Kind?
    @Local private var search = ""
    @Local private var editing: Tx?
    @Local private var deleting: Tx?
    @Local private var accountFilter: UUID?
    @Local private var editingTransfer: Transfer?

    private var rows: [Tx] {
        let q = normalizedPayee(search)
        return model.data.transactions.filter { t in
            (allMonths || model.month.contains(t.date))
                && (kindFilter == nil || t.kind == kindFilter)
                && (model.filter.categoryId == nil || t.categoryId == model.filter.categoryId)
                && (accountFilter == nil || resolvedAccount(t.accountId) == accountFilter)
                && (q.isEmpty || normalizedPayee(t.payee ?? "").contains(q) || normalizedPayee(t.note ?? "").contains(q))
        }
        .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
    }

    /// The account an entry is booked to: its own, or the default (main) one.
    private func resolvedAccount(_ id: UUID?) -> UUID? { id ?? model.data.accounts.first { $0.isMain }?.id }

    /// Transfers shown in the list: none when filtering by category or kind, otherwise those in range.
    private var transfers: [Transfer] {
        guard model.filter.categoryId == nil, kindFilter == nil else { return [] }
        let q = normalizedPayee(search)
        return model.data.transfers.filter { t in
            (allMonths || model.month.contains(t.date))
                && (accountFilter == nil || t.from == accountFilter || t.to == accountFilter)
                && (q.isEmpty || normalizedPayee(t.note ?? "").contains(q))
        }
    }

    var body: some View {
        @Bindable var model = model
        let rows = rows
        let transfers = transfers
        let days = Set(rows.map(\.date) + transfers.map(\.date)).sorted(by: >)
        let spent = rows.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let income = rows.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Transactions") {
                    SearchBox(text: $search, prompt: "Search payee or note")
                    if !allMonths { MonthSwitcher(month: $model.month) }
                }

                HStack(spacing: 10) {
                    RangeChips(options: [("This month", false), ("All time", true)], selection: $allMonths)
                    Divider().frame(height: 18).overlay(Theme.border)
                    RangeChips(options: [("All", Kind?.none), ("Expenses", Kind?.some(.expense)), ("Income", Kind?.some(.income))], selection: $kindFilter)
                    Divider().frame(height: 18).overlay(Theme.border)
                    categoryFilter
                    if model.data.accounts.count > 1 {
                        Divider().frame(height: 18).overlay(Theme.border)
                        InputMenu(options: [("All accounts", UUID?.none)] + model.data.accounts.map { ($0.name, Optional($0.id)) }, selection: $accountFilter)
                            .frame(width: 180)
                    }
                    Spacer()
                }

                HStack(spacing: 14) {
                    summary("Entries", "\(rows.count)", Theme.text)
                    summary("Out", euro(spent), Theme.text)
                    summary("In", euro(income), income > 0 ? Theme.gain : Theme.text)
                }

                VStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty && transfers.isEmpty {
                        Text(search.isEmpty ? "No entries here yet. Press ⌘N to add one." : "Nothing matches \"\(search)\".")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.self) { d in
                            let entries = rows.filter { $0.date == d }
                            let moves = transfers.filter { $0.date == d }
                            let net = entries.reduce(Decimal(0)) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
                            HStack {
                                Text(dayHeading(d))
                                Spacer()
                                Text(signedEuro(net)).monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, 10).padding(.top, d == days.first ? 0 : 18).padding(.bottom, 6)
                            ForEach(entries) { t in row(t) }
                            ForEach(moves) { t in transferRow(t) }
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.border))
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .sheet(item: $editing) { t in QuickAddSheet(editing: t).environment(model) }
        .sheet(item: $editingTransfer) { t in TransferSheet(editing: t).environment(model) }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                let id = deleting?.id
                model.update { $0.transactions.removeAll { $0.id == id } }
                deleting = nil
            }
        } message: { Text(deleting.map { "\($0.payee ?? "Entry"), \(euro($0.amount)) on \(dayText($0.date))" } ?? "") }
    }

    private var categoryFilter: some View {
        @Bindable var model = model
        let c = model.data.category(model.filter.categoryId)
        return Menu {
            Button("All categories") { model.filter.categoryId = nil }
            Divider()
            ForEach(model.data.categories) { cat in
                Button { model.filter.categoryId = cat.id } label: {
                    Label(cat.name + (cat.kind == .income ? " (income)" : ""), systemImage: CategoryIcon.symbol(cat.name, cat.kind))
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let c { Circle().fill(model.data.color(ofCategory: c.id)).frame(width: 7, height: 7) }
                Text(c?.name ?? "All categories")
                if c != nil {
                    Button { model.filter.categoryId = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).help("Clear category filter")
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(c == nil ? Theme.secondary : Theme.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(c == nil ? .clear : Theme.raised))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private func summary(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(color).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.border))
    }

    private func row(_ t: Tx) -> some View {
        let c = model.data.category(t.categoryId)
        return HStack(spacing: 12) {
            CategoryIcon(name: c?.name ?? "", kind: t.kind, color: model.data.color(ofCategory: t.categoryId), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(t.payee ?? c?.name ?? "–").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if t.recurringId != nil {
                        Image(systemName: "repeat").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary).help("Added by a recurring entry")
                    }
                }
                Text([c?.name, model.data.accounts.count > 1 ? model.data.account(resolvedAccount(t.accountId))?.name : nil, t.note]
                        .compactMap { $0 }.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(t.kind == .income ? "+" + euro(t.amount) : "−" + euro(t.amount))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(t.kind == .income ? Theme.gain : Theme.text)
        }
        .hoverRow()
        .onTapGesture { editing = t }
        .contextMenu {
            Button("Edit…") { editing = t }
            Button("Delete…", role: .destructive) { deleting = t }
        }
    }

    private func transferRow(_ t: Transfer) -> some View {
        HStack(spacing: 12) {
            TransferIcon()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("\(model.data.account(t.from)?.name ?? "?") → \(model.data.account(t.to)?.name ?? "?")")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    if t.recurringId != nil { Image(systemName: "repeat").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiary) }
                }
                Text(["Transfer", t.note].compactMap { $0 }.joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(euro(t.amount)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.secondary)
        }
        .hoverRow()
        .onTapGesture { editingTransfer = t }
        .contextMenu {
            Button("Edit…") { editingTransfer = t }
            Button("Delete", role: .destructive) { let id = t.id; model.update { $0.transfers.removeAll { $0.id == id } } }
        }
    }
}

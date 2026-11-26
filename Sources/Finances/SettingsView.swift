import SwiftUI
import FinanceCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Local private var addingRule = false
    @Local private var editingRule: RecurringRule?
    @Local private var deletingRule: RecurringRule?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Settings") { EmptyView() }
                rules
                AccountsSettingsCard()
                HStack(alignment: .top, spacing: 20) {
                    CategoryList(kind: .expense)
                    CategoryList(kind: .income)
                }
                SecurityCard()
                Text("Your data is stored in \(model.store.dataURL.path)")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).textSelection(.enabled)
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .sheet(isPresented: $addingRule) { RuleSheet().environment(model) }
        .sheet(item: $editingRule) { r in RuleSheet(editing: r).environment(model) }
        .confirmationDialog("Delete this recurring entry?", isPresented: Binding(get: { deletingRule != nil }, set: { if !$0 { deletingRule = nil } })) {
            Button("Delete", role: .destructive) {
                let id = deletingRule?.id
                model.update { $0.rules.removeAll { $0.id == id } }
                deletingRule = nil
            }
        } message: { Text("Entries it already added stay.") }
    }

    private func name(_ r: RecurringRule) -> String {
        switch r.target {
        case .trade: return model.data.holding(r.holdingId)?.name ?? "Unknown holding"
        case .transfer: return "\(model.data.account(r.fromAccountId)?.name ?? "?") → \(model.data.account(r.toAccountId)?.name ?? "?")"
        case .transaction: return r.payee ?? model.data.category(r.categoryId)?.name ?? "Unknown"
        }
    }

    private func detail(_ r: RecurringRule) -> String {
        let what = r.target == .trade ? "Savings plan" : r.target == .transfer ? (r.payee.map { "Transfer, \($0)" } ?? "Transfer")
            : (model.data.category(r.categoryId)?.name ?? "")
        let ends = r.endDate.map { ", until \(dayText($0))" } ?? ""
        let month = r.startDate.date().formatted(.dateTime.month(.wide))
        let when: String
        switch r.frequency {
        case .weekly: when = "every \(r.startDate.date().formatted(.dateTime.weekday(.wide)))"
        case .monthly: when = "monthly on the \(ordinal(r.dayOfMonth))"
        case .quarterly: when = "every 3 months on the \(ordinal(r.dayOfMonth)), from \(month)"
        case .yearly: when = "yearly on the \(ordinal(r.dayOfMonth)) of \(month)"
        }
        return "\(what), \(when)\(ends)"
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = Locale(identifier: "en")
        return f.string(from: n as NSNumber) ?? "\(n)"
    }

    private var rules: some View {
        Card(title: "Recurring", link: "Add", icon: "plus", action: { addingRule = true }) {
            if model.data.rules.isEmpty {
                Text("Salary, rent, subscriptions and savings plans: set them up once and they're added on their day.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            VStack(spacing: 2) {
                ForEach(model.data.rules) { r in
                    HStack(spacing: 12) {
                        if r.target == .trade {
                            HoldingIcon(name: model.data.holding(r.holdingId)?.name ?? "?")
                        } else if r.target == .transfer {
                            TransferIcon()
                        } else {
                            let c = model.data.category(r.categoryId)
                            CategoryIcon(name: c?.name ?? "", kind: r.kind ?? .expense, color: model.data.color(ofCategory: r.categoryId), size: 34)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name(r)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                            Text(detail(r)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text((r.kind == .income ? "+" : "") + euro(r.amount)).font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(r.kind == .income ? Theme.gain : Theme.text).monospacedDigit()
                            Text(nextDue(r, after: .today()).map { "next on \(dayText($0))" } ?? "ended")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .hoverRow()
                    .onTapGesture { editingRule = r }
                    .contextMenu {
                        Button("Edit…") { editingRule = r }
                        Button("Delete…", role: .destructive) { deletingRule = r }
                    }
                }
            }
        }
    }
}

private struct CategoryList: View {
    @Environment(AppModel.self) private var model
    var kind: Kind
    @Local private var newName = ""
    @Local private var deleting: TxCategory?
    @Local private var moveTo: UUID?

    var body: some View {
        let cats = model.categories(kind)
        Card(title: kind == .expense ? "Expense categories" : "Income categories") {
            VStack(spacing: 2) {
                ForEach(cats) { c in
                    HStack(spacing: 12) {
                        CategoryIcon(name: c.name, kind: kind, color: model.data.color(ofCategory: c.id), size: 28)
                        CategoryName(category: c)
                        Button { requestDelete(c) } label: { Image(systemName: "trash").font(.system(size: 12)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.tertiary)
                            .disabled(cats.count <= 1).help(cats.count <= 1 ? "Keep at least one category" : "Delete")
                    }
                    .hoverRow()
                }
            }
            HStack(spacing: 8) {
                TextField("", text: $newName, prompt: Text("New category").foregroundColor(Theme.tertiary)).inputStyle().onSubmit(add)
                Button("Add", action: add).buttonStyle(SecondaryButton()).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(item: $deleting) { c in
            VStack(alignment: .leading, spacing: 16) {
                Text("Delete \(c.name)?").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(usage(c)) entries and recurring entries use it. Move them to:").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                CategoryMenu(kind: kind, selection: $moveTo)
                if moveTo == c.id { Text("Pick a different category.").font(.system(size: 12)).foregroundStyle(Theme.loss) }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { deleting = nil }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                    Button("Move and delete") {
                        if let to = moveTo, to != c.id { model.update { deleteCategory(c.id, moveTo: to, &$0) } }
                        deleting = nil
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(moveTo == nil || moveTo == c.id)
                }
            }
            .sheetStyle(width: 380)
            .environment(model)
        }
    }

    private func usage(_ c: TxCategory) -> Int {
        model.data.transactions.filter { $0.categoryId == c.id }.count + model.data.rules.filter { $0.categoryId == c.id }.count
    }

    private func requestDelete(_ c: TxCategory) {
        if usage(c) == 0 {
            model.update { $0.categories.removeAll { $0.id == c.id } }
        } else {
            moveTo = model.categories(kind).first { $0.id != c.id && $0.name == "Other" }?.id ?? model.categories(kind).first { $0.id != c.id }?.id
            deleting = c
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.update { $0.categories.append(TxCategory(name: name, kind: kind)) }
        newName = ""
    }
}

/// Renames on Return or when focus leaves; an empty name is ignored.
private struct CategoryName: View {
    @Environment(AppModel.self) private var model
    var category: TxCategory
    @Local private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .focused($focused)
            .onAppear { text = category.name }
            .onSubmit(commit)
            .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func commit() {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != category.name else { text = category.name; return }
        model.update { d in if let i = d.categories.firstIndex(where: { $0.id == category.id }) { d.categories[i].name = name } }
    }
}

/// Encryption status, lock, and the recovery key.
private struct SecurityCard: View {
    @Environment(AppModel.self) private var model
    @Local private var recovery: String?
    @Local private var copied = false

    var body: some View {
        Card(title: "Security") {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 18)).foregroundStyle(SeriesColor.invested)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(SeriesColor.invested.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your data is encrypted").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text("The key is in this Mac's keychain. The app opens with Touch ID or your Mac password, and locks when the Mac sleeps or the screen locks.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button { model.lock() } label: { Label("Lock now", systemImage: "lock") }.buttonStyle(SecondaryButton())
            }
            if let recovery {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recovery).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
                    HStack {
                        Text("Keep it in your password manager. Without it, a lost keychain means lost data.")
                            .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(recovery, forType: .string)
                            copied = true
                        }
                        .buttonStyle(SecondaryButton())
                        Button("Hide") { self.recovery = nil; copied = false }.buttonStyle(SecondaryButton())
                    }
                }
            } else {
                Button { Task { recovery = await model.revealRecoveryKey() } } label: { Label("Show recovery key", systemImage: "key") }
                    .buttonStyle(SecondaryButton())
            }
        }
    }
}

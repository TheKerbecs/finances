import SwiftUI
import FinanceCore

struct AccountIcon: View {
    var account: Account
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: account.isMain ? "building.columns.fill" : "banknote.fill")
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(SeriesColor.inflow)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(SeriesColor.inflow.opacity(0.16)))
    }
}

/// Enter what the bank or broker app shows right now.
struct CheckinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var embedded = false
    var preset: UUID?

    @Local private var accountId: UUID?
    @Local private var newName = ""
    @Local private var amountText = ""
    @Local private var date = Day.today()
    @Local private var loaded = false
    @FocusState private var amountFocused: Bool

    init(embedded: Bool = false, accountId: UUID? = nil) { self.embedded = embedded; self.preset = accountId }

    /// Balances can be negative (overdraft): a leading minus is allowed.
    private var balance: Decimal? {
        let t = amountText.trimmingCharacters(in: .whitespaces)
        if t == "0" || t == "0,00" || t == "0.00" { return 0 }
        if t.hasPrefix("-") || t.hasPrefix("−") { return parseAmount(String(t.dropFirst())).map { -$0 } }
        return parseAmount(t)
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            if !embedded { Text("Update balance").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text) }
            if model.data.accounts.isEmpty {
                Field(label: "New account") {
                    TextField("", text: $newName, prompt: Text("e.g. Checking account").foregroundColor(Theme.tertiary)).inputStyle()
                }
                Text("Your first account counts as the main one: logged income and expenses go through it. You can change this in Settings.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
                Field(label: "Account") {
                    InputMenu(options: model.data.accounts.map { ($0.name, Optional($0.id)) }, selection: $accountId)
                }
            }
            VStack(spacing: 4) {
                TextField("", text: $amountText, prompt: Text("0,00").foregroundColor(Theme.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                Text(!amountText.isEmpty && balance == nil ? "Not a valid amount" : (balance.map(euro) ?? "Balance shown in your banking app"))
                    .font(.system(size: 12)).foregroundStyle(!amountText.isEmpty && balance == nil ? Theme.loss : Theme.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            Field(label: "As of") { DateInput(day: $date) }.frame(width: 160)
            if let a = model.data.accounts.first(where: { $0.id == accountId }), let exp = expectedBalance(model.data, a, at: date), let b = balance {
                let diff = exp - b
                Text(abs(diff) < 1 ? "Matches what you logged." : diff > 0
                     ? "\(euro(diff)) more went out than you logged since \(dayText(a.latest!.date))."
                     : "\(euro(-diff)) more than expected since \(dayText(a.latest!.date)).")
                    .font(.system(size: 12)).foregroundStyle(abs(diff) < 1 ? Theme.gain : SeriesColor.spent)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button("Save balance") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(balance == nil || (model.data.accounts.isEmpty ? newName.trimmingCharacters(in: .whitespaces).isEmpty : accountId == nil))
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            accountId = preset ?? model.data.accounts.first?.id
            amountFocused = true
        }
        if embedded { content } else { content.sheetStyle() }
    }

    private func save() {
        guard let balance else { return }
        let c = Checkin(date: date, balance: balance)
        let name = newName.trimmingCharacters(in: .whitespaces)
        let target = accountId
        model.update { d in
            if d.accounts.isEmpty {
                d.accounts.append(Account(name: name, isMain: true, paysInvesting: false, checkins: [c]))
            } else if let i = d.accounts.firstIndex(where: { $0.id == target }) {
                d.accounts[i].checkins.removeAll { $0.date == c.date }   // one balance per day
                d.accounts[i].checkins.append(c)
            }
        }
        dismiss()
    }
}

/// Overview card: net worth, each account now and at month end, and spending that wasn't logged.
struct AccountsCard: View {
    @Environment(AppModel.self) private var model
    @Local private var checkin: UUID?
    @Local private var adding = false

    var body: some View {
        let today = Day.today()
        Card(title: "Accounts", link: "Update", icon: "arrow.triangle.2.circlepath", action: { adding = true }) {
            if model.data.accounts.isEmpty {
                Text("Add your bank and broker balances to see your net worth and what your account will show at the end of the month.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Button { adding = true } label: { Label("Add a balance", systemImage: "plus") }.buttonStyle(PrimaryButton())
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net worth").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Money(amount: netWorth(model.data, today: today), size: 30)
                    Text("Accounts plus portfolio").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                }
                VStack(spacing: 4) {
                    ForEach(model.data.accounts) { a in row(a, today: today) }
                }
            }
        }
        .sheet(isPresented: $adding) { CheckinSheet().environment(model) }
        .sheet(item: Binding(get: { checkin.map { IDBox(id: $0) } }, set: { checkin = $0?.id })) { b in
            CheckinSheet(accountId: b.id).environment(model)
        }
    }

    private func row(_ a: Account, today: Day) -> some View {
        let now = expectedBalance(model.data, a, at: today)
        let end = projectedMonthEnd(model.data, a, today: today)
        let gap = unlogged(model.data, a)
        let monthName = monthTitle(today.yearMonth).components(separatedBy: " ").first ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                AccountIcon(account: a)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                    Text(a.latest.map { "Checked \(dayText($0.date)): \(euro($0.balance))" } ?? "No balance yet")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(now.map(euro) ?? "–").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text).monospacedDigit()
                    if let end, end != now {
                        Text("≈ \(euro(end)) end of \(monthName)").font(.system(size: 11)).foregroundStyle(Theme.secondary).monospacedDigit()
                    }
                }
            }
            if let gap, abs(gap.amount) >= 1 {
                Label(gap.amount > 0
                      ? "\(euro(gap.amount)) went out between \(dayText(gap.from)) and \(dayText(gap.to)) that you didn't log."
                      : "\(euro(-gap.amount)) more came in between \(dayText(gap.from)) and \(dayText(gap.to)) than you logged.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(SeriesColor.spent)
                    .padding(.leading, 46)
            }
        }
        .hoverRow()
        .onTapGesture { checkin = a.id }
        .help("Update this balance")
    }
}

struct IDBox: Identifiable { var id: UUID }

/// Settings card: add, rename, switch and delete accounts; recent check-ins.
struct AccountsSettingsCard: View {
    @Environment(AppModel.self) private var model
    @Local private var newName = ""
    @Local private var deleting: Account?

    var body: some View {
        Card(title: "Accounts") {
            if model.data.accounts.isEmpty {
                Text("Add the accounts you check, e.g. your checking account and your broker's cash account.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            ForEach(model.data.accounts) { a in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        AccountIcon(account: a, size: 30)
                        Text(a.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        Spacer()
                        Button { deleting = a } label: { Image(systemName: "trash").font(.system(size: 12)) }
                            .buttonStyle(.plain).foregroundStyle(Theme.tertiary).help("Delete account")
                    }
                    switchRow("Default account for income and expenses", binding(a, \.isMain))
                    switchRow("Default account for savings plans and buys", binding(a, \.paysInvesting))
                    if !a.checkins.isEmpty {
                        let recent = a.checkins.sorted { $0.date > $1.date }.prefix(4)
                        HStack(spacing: 14) {
                            ForEach(Array(recent), id: \.date) { c in
                                HStack(spacing: 4) {
                                    Text("\(dayText(c.date)): \(euro(c.balance))").monospacedDigit()
                                    Button { remove(c, from: a) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                        .buttonStyle(.plain).help("Remove this balance")
                                }
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .toggleStyle(.switch).controlSize(.mini)
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                .padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                TextField("", text: $newName, prompt: Text("New account, e.g. Broker cash").foregroundColor(Theme.tertiary)).inputStyle().onSubmit(add)
                Button("Add", action: add).buttonStyle(SecondaryButton()).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete account and its balances", role: .destructive) {
                guard let id = deleting?.id else { return }
                model.update { d in
                    d.accounts.removeAll { $0.id == id }
                    d.transfers.removeAll { $0.from == id || $0.to == id }
                    d.rules.removeAll { $0.target == .transfer && ($0.fromAccountId == id || $0.toAccountId == id) }
                    for i in d.transactions.indices where d.transactions[i].accountId == id { d.transactions[i].accountId = nil }
                    for i in d.trades.indices where d.trades[i].accountId == id { d.trades[i].accountId = nil }
                    for i in d.rules.indices where d.rules[i].accountId == id { d.rules[i].accountId = nil }
                }
                deleting = nil
            }
        } message: { Text("Entries booked to it move to the default account. Transfers to or from it are deleted.") }
    }

    private func switchRow(_ label: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: on).labelsHidden()
        }
        .padding(.leading, 42)
    }

    private func binding(_ a: Account, _ key: WritableKeyPath<Account, Bool>) -> Binding<Bool> {
        Binding(get: { a[keyPath: key] }, set: { v in
            model.update { d in
                for i in d.accounts.indices where v || d.accounts[i].id == a.id {
                    d.accounts[i][keyPath: key] = v && d.accounts[i].id == a.id   // turning one on turns the others off
                }
            }
        })
    }

    private func remove(_ c: Checkin, from a: Account) {
        model.update { d in if let i = d.accounts.firstIndex(where: { $0.id == a.id }) { d.accounts[i].checkins.removeAll { $0 == c } } }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.update { d in d.accounts.append(Account(name: name, isMain: d.accounts.isEmpty, paysInvesting: false)) }
        newName = ""
    }
}

/// Account picker for a form. nil = the default account (named in the first row).
struct AccountMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    var investing = false

    var body: some View {
        let def = model.data.accounts.first { investing ? $0.paysInvesting : $0.isMain }
        InputMenu(options: [("Default" + (def.map { " (\($0.name))" } ?? ""), UUID?.none)] + model.data.accounts.map { ($0.name, Optional($0.id)) },
                  selection: $selection)
    }
}

/// Move money between two of your accounts, once or on a schedule.
struct TransferSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var editing: Transfer?
    var embedded = false

    @Local private var from: UUID?
    @Local private var to: UUID?
    @Local private var amountText = ""
    @Local private var date = Day.today()
    @Local private var note = ""
    @Local private var repeats: Frequency?
    @Local private var loaded = false
    @Local private var confirmDelete = false

    init(editing: Transfer? = nil, embedded: Bool = false) { self.editing = editing; self.embedded = embedded }

    private var amount: Decimal? { parseAmount(amountText) }

    var body: some View {
        let accounts = model.data.accounts.map { ($0.name, Optional($0.id)) }
        let content = VStack(alignment: .leading, spacing: 18) {
            if !embedded {
                Text(editing == nil ? "New transfer" : "Edit transfer").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            }
            if model.data.accounts.count < 2 {
                Text("Add at least two accounts (Settings → Accounts) to move money between them.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Field(label: "From") { InputMenu(options: accounts, selection: $from) }
                Image(systemName: "arrow.right").foregroundStyle(Theme.secondary).padding(.bottom, 10)
                Field(label: "To") { InputMenu(options: accounts, selection: $to) }
            }
            if from != nil && from == to {
                Text("Pick two different accounts.").font(.system(size: 12)).foregroundStyle(Theme.loss)
            }
            Field(label: "Amount") {
                TextField("", text: $amountText, prompt: Text("€").foregroundColor(Theme.tertiary)).inputStyle()
            }
            HStack(spacing: 12) {
                Field(label: repeats == nil ? "Date" : "Starts") { DateInput(day: $date) }
                if editing == nil { Field(label: "Repeats") { InputMenu(options: repeatOptions, selection: $repeats) } }
            }
            if let repeats { Text(repeatHint(repeats, start: date)).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            Field(label: "Note") {
                TextField("", text: $note, prompt: Text("optional, e.g. savings plan money").foregroundColor(Theme.tertiary)).inputStyle()
            }
            Text("Transfers move money between your accounts. They don't count as income or spending.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            HStack {
                if editing != nil { Button("Delete") { confirmDelete = true }.buttonStyle(SecondaryButton(destructive: true)) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(editing != nil ? "Save" : repeats == nil ? "Add transfer" : "Add recurring transfer") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil || from == nil || to == nil || from == to)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let t = editing {
                from = t.from; to = t.to; amountText = plain(t.amount); date = t.date; note = t.note ?? ""
            } else {
                from = model.data.accounts.first { $0.isMain }?.id ?? model.data.accounts.first?.id
                to = model.data.accounts.first { $0.id != from && $0.paysInvesting }?.id ?? model.data.accounts.first { $0.id != from }?.id
            }
        }
        .confirmationDialog("Delete this transfer?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let id = editing?.id
                model.update { $0.transfers.removeAll { $0.id == id } }
                dismiss()
            }
        }
        if embedded { content } else { content.sheetStyle() }
    }

    private func save() {
        guard let amount, let from, let to, from != to else { return }
        let n = note.trimmingCharacters(in: .whitespaces)
        if editing == nil, let repeats {
            model.update { $0.rules.append(ruleForTransfer(repeats, date: date, amount: amount, from: from, to: to, note: n.isEmpty ? nil : n)) }
        } else {
            var t = editing ?? Transfer(date: date, amount: amount, from: from, to: to)
            t.date = date; t.amount = amount; t.from = from; t.to = to; t.note = n.isEmpty ? nil : n
            model.update { d in
                if let i = d.transfers.firstIndex(where: { $0.id == t.id }) { d.transfers[i] = t } else { d.transfers.append(t) }
            }
        }
        dismiss()
    }
}

struct TransferIcon: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(Theme.raised))
    }
}

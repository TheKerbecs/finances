import SwiftUI
import FinanceCore

/// Add or edit a recurring rule: a regular income/expense or a savings plan.
struct RuleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var editing: RecurringRule?

    @Local private var target: RuleTarget = .transaction
    @Local private var kind: Kind = .expense
    @Local private var categoryId: UUID?
    @Local private var payee = ""
    @Local private var holdingId: UUID?
    @Local private var amountText = ""
    @Local private var frequency: Frequency = .monthly
    @Local private var dayOfMonth = 1
    @Local private var startDate = Day.today()
    @Local private var hasEnd = false
    @Local private var endDate = Day.today().adding(days: 365)
    @Local private var loaded = false
    @Local private var accountId: UUID?
    @Local private var fromId: UUID?
    @Local private var toId: UUID?

    init(editing: RecurringRule? = nil) { self.editing = editing }

    private var draft: RecurringRule? {
        guard let amount = parseAmount(amountText) else { return nil }
        if target == .transaction && categoryId == nil { return nil }
        if target == .trade && holdingId == nil { return nil }
        if target == .transfer && (fromId == nil || toId == nil || fromId == toId) { return nil }
        let p = payee.trimmingCharacters(in: .whitespaces)
        var r = editing ?? RecurringRule(target: target, amount: amount, frequency: frequency, dayOfMonth: dayOfMonth, startDate: startDate)
        r.target = target; r.amount = amount; r.frequency = frequency; r.dayOfMonth = dayOfMonth; r.startDate = startDate
        r.endDate = hasEnd ? endDate : nil
        r.kind = target == .transaction ? kind : nil
        r.categoryId = target == .transaction ? categoryId : nil
        r.payee = target == .transaction && !p.isEmpty ? p : nil
        r.holdingId = target == .trade ? holdingId : nil
        r.accountId = target == .transfer ? nil : accountId
        r.fromAccountId = target == .transfer ? fromId : nil
        r.toAccountId = target == .transfer ? toId : nil
        if target == .transfer { r.payee = p.isEmpty ? nil : p }
        return r
    }

    private var scheduleText: String {
        let month = startDate.date().formatted(.dateTime.month(.wide))
        switch frequency {
        case .weekly: return "Every \(startDate.date().formatted(.dateTime.weekday(.wide))), starting \(dayText(startDate))."
        case .monthly: return "Every month on day \(dayOfMonth)."
        case .quarterly: return "Every 3 months on day \(dayOfMonth), counting from \(month)."
        case .yearly: return "Every year on day \(dayOfMonth) of \(month)."
        }
    }

    /// Entries saving would add right away (only for a new rule; an edited one continues after its last entry).
    private var backfill: Int {
        guard editing == nil, let d = draft else { return 0 }
        return occurrences(of: d, through: .today()).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editing == nil ? "New recurring entry" : "Edit recurring entry").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            if editing == nil {
                RangeChips(options: [("Money in/out", RuleTarget.transaction), ("Savings plan", RuleTarget.trade), ("Transfer", RuleTarget.transfer)], selection: $target)
            }

            if target == .transaction {
                RangeChips(options: [("Expense", Kind.expense), ("Income", Kind.income)], selection: $kind)
                HStack(spacing: 12) {
                    Field(label: "Category") { CategoryMenu(kind: kind, selection: $categoryId) }
                    Field(label: "Payee") {
                        TextField("", text: $payee, prompt: Text("e.g. Landlord").foregroundColor(Theme.tertiary)).inputStyle()
                    }
                }
                if !model.data.accounts.isEmpty { Field(label: "Account") { AccountMenu(selection: $accountId) } }
            } else if target == .transfer {
                let accounts = model.data.accounts.map { ($0.name, Optional($0.id)) }
                if model.data.accounts.count < 2 {
                    Text("Add at least two accounts under Settings → Accounts first.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Field(label: "From") { InputMenu(options: accounts, selection: $fromId) }
                    Image(systemName: "arrow.right").foregroundStyle(Theme.secondary).padding(.bottom, 10)
                    Field(label: "To") { InputMenu(options: accounts, selection: $toId) }
                }
                Field(label: "Note") {
                    TextField("", text: $payee, prompt: Text("optional").foregroundColor(Theme.tertiary)).inputStyle()
                }
            } else if model.data.holdings.isEmpty {
                Text("Add the holding under Investments first.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            } else {
                HStack(spacing: 12) {
                    Field(label: "Holding") {
                        InputMenu(options: model.data.holdings.map { ("\($0.name) (\($0.ticker))", Optional($0.id)) }, selection: $holdingId)
                    }
                    if !model.data.accounts.isEmpty { Field(label: "Paid from") { AccountMenu(selection: $accountId, investing: true) } }
                }
            }

            HStack(spacing: 12) {
                Field(label: "Amount") {
                    TextField("", text: $amountText, prompt: Text("€").foregroundColor(Theme.tertiary)).inputStyle()
                }
                Field(label: "Repeats") {
                    InputMenu(options: [("Weekly", Frequency.weekly), ("Monthly", .monthly), ("Every 3 months", .quarterly), ("Yearly", .yearly)],
                              selection: $frequency)
                }
                if frequency != .weekly {
                    Field(label: "On day") {
                        InputMenu(options: (1...31).map { ("\($0)", $0) }, selection: $dayOfMonth)
                    }
                    .frame(width: 90)
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                Field(label: "Starts") { DateInput(day: $startDate) }
                Field(label: "Ends") {
                    if hasEnd {
                        HStack(spacing: 6) {
                            DateInput(day: $endDate)
                            Button { hasEnd = false } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("No end date")
                        }
                    } else {
                        Button("Never (set an end)") { hasEnd = true }.buttonStyle(SecondaryButton())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scheduleText)
                if frequency != .weekly && dayOfMonth > 28 { Text("In shorter months it falls on the last day.") }
                if backfill > 0 {
                    Text("This adds \(backfill) past \(backfill == 1 ? "entry" : "entries") now.").foregroundStyle(SeriesColor.spent)
                    if target == .trade {
                        Text("Don't also enter a starting position for this period, or it's counted twice.").foregroundStyle(SeriesColor.spent)
                    }
                }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(editing == nil ? "Add recurring entry" : "Save") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil)
            }
        }
        .sheetStyle(width: 540)
        .onAppear(perform: load)
        .onChange(of: kind) { _, k in
            if model.data.category(categoryId)?.kind != k { categoryId = model.categories(k).first?.id }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let r = editing {
            target = r.target; kind = r.kind ?? .expense; categoryId = r.categoryId; payee = r.payee ?? ""
            holdingId = r.holdingId; amountText = plain(r.amount); frequency = r.frequency
            accountId = r.accountId; fromId = r.fromAccountId; toId = r.toAccountId
            dayOfMonth = r.dayOfMonth; startDate = r.startDate
            if let e = r.endDate { hasEnd = true; endDate = e }
        } else {
            categoryId = model.categories(.expense).first?.id
            holdingId = model.data.holdings.first?.id
            dayOfMonth = Day.today().day
            fromId = model.data.accounts.first { $0.isMain }?.id ?? model.data.accounts.first?.id
            toId = model.data.accounts.first { $0.id != fromId }?.id
        }
    }

    private func save() {
        guard let r = draft else { return }
        model.update { d in
            if let i = d.rules.firstIndex(where: { $0.id == r.id }) { d.rules[i] = r } else { d.rules.append(r) }
        }
        dismiss()
    }
}

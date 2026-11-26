import SwiftUI
import FinanceCore

/// Add or edit one income/expense entry. Amount is focused; Return saves, Esc cancels.
struct QuickAddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var editing: Tx?
    var embedded = false   // inside NewEntrySheet, which owns the chrome

    @Local private var amountText = ""
    @Local private var kind: Kind = .expense
    @Local private var payee = ""
    @Local private var categoryId: UUID?
    @Local private var date = Day.today()
    @Local private var note = ""
    @Local private var categoryTouched = false
    @Local private var loaded = false
    @Local private var confirmDelete = false
    @Local private var repeats: Frequency?
    @Local private var accountId: UUID?
    @FocusState private var amountFocused: Bool

    init(editing: Tx? = nil, embedded: Bool = false) { self.editing = editing; self.embedded = embedded }

    private var amount: Decimal? { parseAmount(amountText) }
    private var suggestions: [String] {
        guard !payee.isEmpty else { return [] }
        let s = payeeSuggestions(payee, in: model.data, limit: 4)
        return s.count == 1 && s[0] == payee ? [] : s
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            if !embedded {
                Text(editing == nil ? "New entry" : "Edit entry").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            }
            RangeChips(options: [("Expense", Kind.expense), ("Income", Kind.income)], selection: $kind)

            VStack(spacing: 4) {
                TextField("", text: $amountText, prompt: Text("0,00").foregroundColor(Theme.tertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(kind == .income ? Theme.gain : Theme.text)
                    .multilineTextAlignment(.center)
                    .focused($amountFocused)
                Text(!amountText.isEmpty && amount == nil ? "Not a valid amount" : (amount.map(euro) ?? "Amount in €"))
                    .font(.system(size: 12)).foregroundStyle(!amountText.isEmpty && amount == nil ? Theme.loss : Theme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            Field(label: "Payee") {
                TextField("", text: $payee, prompt: Text("e.g. Rewe").foregroundColor(Theme.tertiary)).inputStyle()
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { s in
                            Button { pickPayee(s) } label: {
                                Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Capsule().fill(Theme.raised))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Field(label: "Category") { CategoryMenu(kind: kind, selection: $categoryId) { categoryTouched = true } }
                if !model.data.accounts.isEmpty { Field(label: "Account") { AccountMenu(selection: $accountId) } }
            }
            HStack(spacing: 12) {
                Field(label: repeats == nil ? "Date" : "Starts") { DateInput(day: $date) }
                if editing == nil {
                    Field(label: "Repeats") { InputMenu(options: repeatOptions, selection: $repeats) }
                }
            }
            if let repeats { Text(repeatHint(repeats, start: date)).font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            Field(label: "Note") {
                TextField("", text: $note, prompt: Text("optional").foregroundColor(Theme.tertiary)).inputStyle()
            }
            if editing?.recurringId != nil {
                Label("Added by a recurring entry", systemImage: "repeat").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }

            HStack {
                if editing != nil {
                    Button("Delete") { confirmDelete = true }.buttonStyle(SecondaryButton(destructive: true))
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(editing != nil ? "Save" : repeats == nil ? "Add entry" : "Add recurring entry") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil || categoryId == nil)
            }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, k in
            if model.data.category(categoryId)?.kind != k { categoryId = model.categories(k).first?.id }
        }
        .onChange(of: payee) { _, p in
            guard !categoryTouched, let c = lastCategory(forPayee: p, in: model.data),
                  let cat = model.data.category(c) else { return }
            kind = cat.kind
            categoryId = c
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let id = editing?.id
                model.update { $0.transactions.removeAll { $0.id == id } }
                dismiss()
            }
        }

        if embedded { content } else { content.sheetStyle() }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let t = editing {
            amountText = plain(t.amount)
            kind = t.kind
            payee = t.payee ?? ""
            categoryId = t.categoryId
            accountId = t.accountId
            date = t.date
            note = t.note ?? ""
            categoryTouched = true
        } else {
            categoryId = model.categories(.expense).first { $0.name == "Groceries" }?.id ?? model.categories(.expense).first?.id
        }
        amountFocused = true
    }

    private func pickPayee(_ s: String) {
        payee = s
        if let c = lastCategory(forPayee: s, in: model.data), let cat = model.data.category(c) {
            kind = cat.kind
            categoryId = c
            categoryTouched = true
        }
    }

    private func save() {
        guard let amount, let categoryId else { return }
        let trimmedPayee = payee.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if editing == nil, let repeats {
            var rule = ruleForRepeat(repeats, date: date, amount: amount, kind: kind, categoryId: categoryId,
                                     payee: trimmedPayee.isEmpty ? nil : trimmedPayee)
            rule.accountId = accountId
            model.update { $0.rules.append(rule) }   // update() creates the entries that are already due
            dismiss()
            return
        }
        var t = editing ?? Tx(date: date, amount: amount, kind: kind, categoryId: categoryId)
        t.date = date; t.amount = amount; t.kind = kind; t.categoryId = categoryId; t.accountId = accountId
        t.payee = trimmedPayee.isEmpty ? nil : trimmedPayee
        t.note = trimmedNote.isEmpty ? nil : trimmedNote
        model.update { d in
            if let i = d.transactions.firstIndex(where: { $0.id == t.id }) { d.transactions[i] = t } else { d.transactions.append(t) }
        }
        dismiss()
    }
}

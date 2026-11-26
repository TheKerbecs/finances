import SwiftUI
import FinanceCore

/// Add or edit a buy/sell. Fill any two of amount, units and price; the third is worked out.
struct TradeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var editing: Trade?
    var presetHolding: UUID?
    var embedded = false

    @Local private var holdingId: UUID?
    @Local private var side: Side = .buy
    @Local private var date = Day.today()
    @Local private var amountText = ""
    @Local private var unitsText = ""
    @Local private var priceText = ""
    @Local private var note = ""
    @Local private var loaded = false
    @Local private var confirmDelete = false
    @Local private var repeats: Frequency?
    @Local private var accountId: UUID?

    init(editing: Trade? = nil, holdingId: UUID? = nil, embedded: Bool = false) {
        self.editing = editing; self.presetHolding = holdingId; self.embedded = embedded
    }

    /// (amount, units, price) with the missing one computed, or nil while fewer than two are valid.
    private var resolved: (Decimal, Decimal, Decimal)? {
        let a = parseAmount(amountText), u = parseNumber(unitsText), p = parseNumber(priceText)
        switch (a, u, p) {
        case let (a?, u?, p?): return (a, u, p)
        case let (a?, u?, nil): return (a, u, roundTo(a / u, 4))
        case let (a?, nil, p?): return (a, roundTo(a / p, 6), p)
        case let (nil, u?, p?): return (roundTo(u * p, 2), u, p)
        default: return nil
        }
    }

    private var held: Decimal {
        guard let holdingId else { return 0 }
        return unitsHeld(holdingId, on: date, trades: model.data.trades, excluding: editing?.id)
    }

    private var sellTooBig: Bool {
        guard side == .sell, let r = resolved else { return false }
        return r.1 > held
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 18) {
            if !embedded {
                Text(editing == nil ? "New trade" : "Edit trade").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            }
            if model.data.holdings.isEmpty {
                Text("Add a holding first under Investments.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            if repeats == nil { RangeChips(options: [("Buy", Side.buy), ("Sell", Side.sell)], selection: $side) }
            HStack(spacing: 12) {
                Field(label: "Holding") {
                    InputMenu(options: model.data.holdings.map { ("\($0.name) (\($0.ticker))", Optional($0.id)) }, selection: $holdingId)
                }
                if !model.data.accounts.isEmpty {
                    Field(label: side == .buy ? "Paid from" : "Paid into") { AccountMenu(selection: $accountId, investing: true) }
                }
            }
            HStack(spacing: 12) {
                Field(label: repeats == nil ? "Date" : "Starts") { DateInput(day: $date) }
                if editing == nil {
                    Field(label: "Repeats") { InputMenu(options: repeatOptions, selection: $repeats) }
                }
            }
            if let repeats {
                Field(label: "Amount each time") {
                    TextField("", text: $amountText, prompt: Text("€").foregroundColor(Theme.tertiary)).inputStyle()
                }
                Text(repeatHint(repeats, start: date) + " Units are worked out from the closing price.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
            HStack(spacing: 12) {
                Field(label: side == .buy ? "Amount paid" : "Amount received") {
                    TextField("", text: $amountText, prompt: Text("incl. fees").foregroundColor(Theme.tertiary)).inputStyle()
                }
                Field(label: "Units") {
                    TextField("", text: $unitsText, prompt: Text("e.g. 3,1952").foregroundColor(Theme.tertiary)).inputStyle()
                }
                Field(label: "Price per unit") {
                    TextField("", text: $priceText, prompt: Text("€").foregroundColor(Theme.tertiary)).inputStyle()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let r = resolved {
                    Text("\(units(r.1)) units × \(euro(r.2)) = \(euro(r.0))").foregroundStyle(Theme.text)
                } else {
                    Text("Fill in any two of amount, units and price.")
                }
                if sellTooBig {
                    Text("You only hold \(units(held)) units on that date.").foregroundStyle(Theme.loss)
                }
                if editing?.unitsEstimated == true {
                    Text("Units were estimated from the closing price. Saving marks them as checked.")
                }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            Field(label: "Note") {
                TextField("", text: $note, prompt: Text("optional").foregroundColor(Theme.tertiary)).inputStyle()
            }

            HStack {
                if editing != nil {
                    Button("Delete") { confirmDelete = true }.buttonStyle(SecondaryButton(destructive: true))
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(editing != nil ? "Save" : repeats == nil ? "Add trade" : "Add savings plan") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(holdingId == nil || (repeats == nil ? (resolved == nil || sellTooBig) : parseAmount(amountText) == nil))
            }
        }
        .onAppear(perform: load)
        .confirmationDialog("Delete this trade?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                let id = editing?.id
                model.update { $0.trades.removeAll { $0.id == id } }
                dismiss()
            }
        }

        if embedded { content } else { content.sheetStyle(width: 520) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let t = editing {
            holdingId = t.holdingId; side = t.side; date = t.date; accountId = t.accountId
            amountText = plain(t.amount)
            unitsText = t.units > 0 ? plain(t.units) : ""
            priceText = t.pricePerUnit > 0 ? plain(t.pricePerUnit) : ""
            note = t.note ?? ""
        } else {
            holdingId = presetHolding ?? model.data.holdings.first?.id
        }
    }

    private func save() {
        if editing == nil, let repeats, let holdingId, let amount = parseAmount(amountText) {
            var rule = ruleForRepeat(repeats, date: date, amount: amount, holdingId: holdingId)
            rule.accountId = accountId
            model.update { $0.rules.append(rule) }
            dismiss()
            return
        }
        guard let (a, u, p) = resolved, let holdingId else { return }
        var t = editing ?? Trade(holdingId: holdingId, date: date, side: side, amount: a, units: u, pricePerUnit: p)
        t.holdingId = holdingId; t.date = date; t.side = side; t.amount = a; t.units = u; t.pricePerUnit = p
        t.unitsEstimated = false
        t.accountId = accountId
        let n = note.trimmingCharacters(in: .whitespaces)
        t.note = n.isEmpty ? nil : n
        model.update { d in
            if let i = d.trades.firstIndex(where: { $0.id == t.id }) { d.trades[i] = t } else { d.trades.append(t) }
        }
        dismiss()
    }
}

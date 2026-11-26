import SwiftUI
import FinanceCore

/// Find a listing by name (or type a ticker). Only EUR listings can be saved.
struct AddHoldingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Local private var query = ""
    @Local private var hits: [SymbolHit] = []
    @Local private var searching = false
    @Local private var ticker = ""
    @Local private var name = ""
    @Local private var checking = false
    @Local private var message: String?
    var initialQuery = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add holding").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                TextField("", text: $query, prompt: Text("Name or ISIN, e.g. VanEck Semiconductor").foregroundColor(Theme.tertiary))
                    .textFieldStyle(.plain)
                if searching { ProgressView().controlSize(.small) }
            }
            .inputStyle()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(hits) { h in
                        let on = h.symbol == ticker
                        let eur = isEURListing(h)
                        Button { ticker = h.symbol; name = h.name; message = nil } label: {
                            HStack(spacing: 12) {
                                HoldingIcon(name: h.name, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(h.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text("\(h.symbol), \(exchangeName(h.exchange))").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                Text(eur ? "EUR" : "not EUR")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(eur ? Theme.gain : Theme.tertiary)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(eur ? Theme.gain.opacity(0.14) : Theme.raised))
                                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.raised : .clear))
                            .opacity(eur || on ? 1 : 0.55)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 200)
            .overlay {
                if hits.isEmpty && !searching {
                    Text(query.count < 2 ? "Type at least two letters." : "No results.").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                }
            }
            Text("Pick a listing marked EUR. Xetra (ticker ending .DE) is listed first.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack(spacing: 12) {
                Field(label: "Ticker") {
                    TextField("", text: $ticker, prompt: Text("e.g. EUNL.DE").foregroundColor(Theme.tertiary)).inputStyle()
                }
                .frame(width: 150)
                Field(label: "Name") {
                    TextField("", text: $name, prompt: Text("shown in the app").foregroundColor(Theme.tertiary)).inputStyle()
                }
            }
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(Theme.loss) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(checking ? "Checking…" : "Add holding") { Task { await save() } }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(ticker.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            }
        }
        .sheetStyle(width: 520)
        .onAppear { if query.isEmpty && !initialQuery.isEmpty { query = initialQuery } }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { hits = []; return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            searching = true
            hits = (try? await Yahoo.search(q)) ?? []
            searching = false
        }
    }

    private func save() async {
        let t = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        if model.data.holdings.contains(where: { $0.ticker == t }) { message = "\(t) is already in your holdings."; return }
        checking = true
        defer { checking = false }
        var h = Holding(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? t : name, ticker: t)
        do {
            let q = try await Yahoo.chart(t, from: nil)
            guard q.currency == "EUR" else {
                message = "\(t) trades in \(q.currency.isEmpty ? "an unknown currency" : q.currency). European brokers sell the UCITS versions: pick a listing marked EUR, ideally Xetra (.DE)."
                return
            }
            h.lastPrice = q.price
            h.lastPriceDate = q.closes.keys.max() ?? .today()
        } catch let e as PriceError where e.description.contains("No price data") || e.description.contains("404") {
            message = "No prices found for \(t). Check the ticker."
            return
        } catch {
            // offline: allow saving without a price
        }
        model.update { $0.holdings.append(h) }
        dismiss()
    }
}

struct SetPriceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var holding: Holding
    @Local private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set price").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
            Field(label: "Price per unit of \(holding.name)") {
                TextField("", text: $text, prompt: Text("€").foregroundColor(Theme.tertiary)).inputStyle()
            }
            Text("The next price refresh replaces it.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button("Set price") {
                    guard let p = parseNumber(text) else { return }
                    model.update { d in
                        if let i = d.holdings.firstIndex(where: { $0.id == holding.id }) {
                            d.holdings[i].lastPrice = p
                            d.holdings[i].lastPriceDate = .today()
                        }
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .disabled(parseNumber(text) == nil)
            }
        }
        .sheetStyle(width: 360)
    }
}

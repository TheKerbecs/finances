import SwiftUI
import FinanceCore

struct InvestmentsView: View {
    @Environment(AppModel.self) private var model
    @Local private var selectedHolding: UUID?
    @Local private var addingHolding = false
    @Local private var newTrade = false
    @Local private var editingTrade: Trade?
    @Local private var pricing: Holding?
    @Local private var deletingHolding: Holding?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Investments") {
                    if model.refreshing {
                        ProgressView().controlSize(.small).frame(width: 42)
                    } else {
                        IconButton(symbol: "arrow.clockwise", help: "Refresh prices") { Task { await model.refreshPrices() } }
                            .disabled(model.data.holdings.isEmpty)
                    }
                    Button { newTrade = true } label: { Label("Add trade", systemImage: "plus") }
                        .buttonStyle(SecondaryButton()).disabled(model.data.holdings.isEmpty)
                    Button { addingHolding = true } label: { Label("Add holding", systemImage: "plus") }
                        .buttonStyle(PrimaryButton())
                }
                if let err = model.priceError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(SeriesColor.spent)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(SeriesColor.spent.opacity(0.12)))
                }

                if model.data.holdings.isEmpty {
                    Card(title: "No holdings yet") {
                        Text("Add your ETFs and stocks, for example the iShares Core MSCI World (EUNL.DE). Then add your trades or set up a savings plan under Settings.")
                            .font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        Button { addingHolding = true } label: { Label("Add holding", systemImage: "plus") }.buttonStyle(PrimaryButton())
                    }
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        PortfolioCard(linkToInvestments: false).frame(maxWidth: .infinity)
                        holdingsCard.frame(maxWidth: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    tradesCard
                }
            }
            .padding(28)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
        .onAppear {
            if selectedHolding == nil { selectedHolding = model.data.holdings.first?.id }
            if model.snapshotAddHolding != nil { addingHolding = true }
        }
        .sheet(isPresented: $addingHolding) { AddHoldingSheet(initialQuery: model.snapshotAddHolding ?? "").environment(model) }
        .sheet(isPresented: $newTrade) { TradeSheet(holdingId: selectedHolding).environment(model) }
        .sheet(item: $editingTrade) { t in TradeSheet(editing: t).environment(model) }
        .sheet(item: $pricing) { h in SetPriceSheet(holding: h).environment(model) }
        .confirmationDialog("Delete \(deletingHolding?.name ?? "")?", isPresented: Binding(get: { deletingHolding != nil }, set: { if !$0 { deletingHolding = nil } })) {
            Button("Delete holding, its trades and savings plans", role: .destructive) {
                guard let h = deletingHolding else { return }
                model.update { d in
                    d.holdings.removeAll { $0.id == h.id }
                    d.trades.removeAll { $0.holdingId == h.id }
                    d.rules.removeAll { $0.holdingId == h.id }
                }
                selectedHolding = model.data.holdings.first?.id
                deletingHolding = nil
            }
        } message: {
            Text("\(model.data.trades.filter { $0.holdingId == deletingHolding?.id }.count) trades are deleted with it.")
        }
    }

    private var holdingsCard: some View {
        Card(title: "Holdings") {
            VStack(spacing: 4) {
                ForEach(model.positions()) { p in
                    if let h = model.data.holding(p.id) {
                        let on = selectedHolding == h.id
                        HStack(spacing: 12) {
                            HoldingIcon(name: h.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text("\(h.ticker), \(units(p.units)) units").font(.system(size: 11)).foregroundStyle(Theme.secondary).monospacedDigit()
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(p.worth.map(euro) ?? "No price").font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.text).monospacedDigit()
                                HStack(spacing: 6) {
                                    Text(p.gain.map(signedEuro) ?? "").font(.system(size: 11)).foregroundStyle(Theme.gainColor(p.gain)).monospacedDigit()
                                    if p.gainPercent != nil { ChangeBadge(percent: p.gainPercent, value: p.gain).scaleEffect(0.9) }
                                }
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.raised : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedHolding = h.id }
                        .contextMenu {
                            Button("Add trade…") { selectedHolding = h.id; newTrade = true }
                            Button("Set price by hand…") { pricing = h }
                            Divider()
                            Button("Delete holding…", role: .destructive) { deletingHolding = h }
                        }
                        if let d = h.lastPriceDate, on {
                            Text("Price \(h.lastPrice.map(euro) ?? "–") from \(dayText(d))")
                                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var tradesCard: some View {
        if let hid = selectedHolding, let h = model.data.holding(hid) {
            let trades = model.data.trades.filter { $0.holdingId == hid }.sorted { $0.date > $1.date }
            Card(title: "Trades in \(h.name)") {
                if trades.isEmpty {
                    Text("No trades yet. Add one, or set up a savings plan under Settings.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
                LazyVStack(spacing: 0) {
                    ForEach(trades) { t in
                        HStack(spacing: 12) {
                            Image(systemName: t.side == .buy ? "arrow.down.left" : "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(t.side == .buy ? SeriesColor.invested : SeriesColor.spent)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 9).fill((t.side == .buy ? SeriesColor.invested : SeriesColor.spent).opacity(0.15)))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(t.side == .buy ? "Buy" : "Sell").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                    if t.recurringId != nil { Text("Savings plan").font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
                                }
                                Text(dayText(t.date)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                if t.unitsEstimated {
                                    Image(systemName: t.units == 0 ? "hourglass" : "questionmark.circle")
                                        .font(.system(size: 11)).foregroundStyle(SeriesColor.spent)
                                        .help(t.units == 0 ? "Waiting for the closing price" : "Worked out from the closing price. Click to enter the exact units from your broker.")
                                }
                                Text(t.units == 0 ? "–" : "\(units(t.units)) × \(euro(t.pricePerUnit))")
                                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
                            }
                            Text(euro(t.amount)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                                .monospacedDigit().frame(minWidth: 90, alignment: .trailing)
                        }
                        .hoverRow()
                        .onTapGesture { editingTrade = t }
                        .contextMenu {
                            Button("Edit…") { editingTrade = t }
                            Button("Delete", role: .destructive) { let id = t.id; model.update { $0.trades.removeAll { $0.id == id } } }
                        }
                    }
                }
            }
        }
    }
}

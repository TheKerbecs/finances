import SwiftUI
import FinanceCore

/// ⌘N: income/expense or an investment trade.
struct NewEntrySheet: View {
    @Environment(AppModel.self) private var model
    @Local private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New entry").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                Spacer()
                RangeChips(options: [("Money", 0), ("Investment", 1), ("Transfer", 3), ("Balance", 2)], selection: $tab)
            }
            switch tab {
            case 1: TradeSheet(embedded: true)
            case 2: CheckinSheet(embedded: true)
            case 3: TransferSheet(embedded: true)
            default: QuickAddSheet(embedded: true)
            }
        }
        .sheetStyle(width: 520)
        .onAppear { if let t = model.snapshotTab { tab = t } }
    }
}

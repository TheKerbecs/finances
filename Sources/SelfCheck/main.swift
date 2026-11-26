import Foundation
import FinanceCore

runCoreChecks()
runStoreChecks()
runLedgerChecks()
runRecurringChecks()
runSettingsChecks()
runPortfolioChecks()
runPriceChecks()
runAnalyticsChecks()
runAccountChecks()
runTransferChecks()
print("SelfCheck OK")

if CommandLine.arguments.contains("--live") {
    let q = try await Yahoo.chart("EUNL.DE", from: Day.today().adding(days: -10))
    print("EUNL.DE", q.price, q.currency, "closes:", q.closes.count)
    for q in ["MSCI World", "VanEck Semiconductor", "IE00BMC38736", "Semiconductor"] {
        print("search \(q):", try await Yahoo.search(q).prefix(4).map { "\($0.symbol) (\(exchangeName($0.exchange))\(isEURListing($0) ? ", EUR" : ""))" }.joined(separator: ", "))
    }
}

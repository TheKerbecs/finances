import Foundation
import FinanceCore

func runPriceChecks() {
    let json = #"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":125.825,"exchangeTimezoneName":"Europe/Berlin"},"timestamp":[1795507200,1795593600,1795680000],"indicators":{"quote":[{"close":[120.5,null,125.825]}]}}],"error":null}}"#
    let q = try! parseChart(Data(json.utf8))
    precondition(q.price == dec("125.825") && q.currency == "EUR")
    precondition(q.closes == [day("2026-11-24"): dec("120.5"), day("2026-11-26"): dec("125.825")])
    precondition(close(on: day("2026-11-25"), in: q.closes) == dec("120.5"))
    precondition(close(on: day("2026-11-26"), in: q.closes) == dec("125.825"))
    precondition(close(on: day("2026-11-23"), in: q.closes) == nil)
    // Yahoo closes are float32-noisy: 129.92999267578125 means 129.93
    let noisy = try! parseChart(Data(#"{"chart":{"result":[{"meta":{"currency":"EUR","regularMarketPrice":129.92999267578125},"timestamp":[1795507200],"indicators":{"quote":[{"close":[129.92999267578125]}]}}]}}"#.utf8))
    precondition(noisy.closes[day("2026-11-24")] == dec("129.93") && noisy.price == dec("129.93"))
    // error payload throws
    precondition((try? parseChart(Data(#"{"chart":{"result":null,"error":{"code":"Not Found"}}}"#.utf8))) == nil)

    let s = try! parseSearch(Data(#"{"quotes":[{"symbol":"EUNL.DE","exchange":"GER","longname":"iShares Core MSCI World"},{"exchange":"X"},{"symbol":"IWDA.L","exchange":"LSE","shortname":"ISHARES CORE"}]}"#.utf8))
    precondition(s == [SymbolHit(symbol: "EUNL.DE", exchange: "GER", name: "iShares Core MSCI World"),
                       SymbolHit(symbol: "IWDA.L", exchange: "LSE", name: "ISHARES CORE")])

    var d = FinanceData.defaults()
    let h = Holding(name: "MSCI World", ticker: "EUNL.DE")
    d.holdings = [h]
    d.trades = [
        Trade(holdingId: h.id, date: day("2026-11-25"), side: .buy, amount: 400, units: 0, pricePerUnit: 0, unitsEstimated: true),
        Trade(holdingId: h.id, date: day("2026-11-25"), side: .buy, amount: 100, units: 1, pricePerUnit: 100),
        Trade(holdingId: h.id, date: day("2026-11-20"), side: .buy, amount: 400, units: 0, pricePerUnit: 0, unitsEstimated: true),
    ]
    precondition(fillEstimatedUnits(&d, closes: [h.id: q.closes]) == 1)
    precondition(d.trades[0].pricePerUnit == dec("120.5") && d.trades[0].units == dec("3.319502") && d.trades[0].unitsEstimated)
    precondition(d.trades[1].units == 1 && d.trades[1].pricePerUnit == 100)
    precondition(d.trades[2].units == 0)   // no close on or before 11-20: retried later
    precondition(fillEstimatedUnits(&d, closes: [h.id: q.closes]) == 0)

    let cache = PriceCache(directory: tempDir().appendingPathComponent("prices"))
    precondition(cache.load("EUNL.DE").isEmpty)
    cache.save("EUNL.DE", q.closes)
    precondition(cache.load("EUNL.DE") == q.closes)

    // EUR listings first, Xetra on top; non-EUR kept but last
    let raw = [SymbolHit(symbol: "SMH", exchange: "NGM", name: "VanEck Semiconductor ETF"),
               SymbolHit(symbol: "SMH.L", exchange: "LSE", name: "VanEck Semiconductor UCITS ETF"),
               SymbolHit(symbol: "SMH.MI", exchange: "MIL", name: "VanEck Semiconductor UCITS ETF"),
               SymbolHit(symbol: "VVSM.DE", exchange: "GER", name: "VanEck Semiconductor UCITS ETF")]
    precondition(rankHits(raw).map(\.symbol) == ["VVSM.DE", "SMH.MI", "SMH", "SMH.L"])
    precondition(rankHits(raw + raw).count == 4)   // duplicates from a merged ISIN + name search
    precondition(isEURListing(raw[3]) && isEURListing(raw[2]) && !isEURListing(raw[0]) && !isEURListing(raw[1]))
    precondition(exchangeName("GER") == "Xetra" && exchangeName("XYZ") == "XYZ")
    precondition(looksLikeISIN("IE00BMC38736") && looksLikeISIN(" ie00bmc38736 ") && !looksLikeISIN("VanEck") && !looksLikeISIN("VVSM.DE"))

    // generic names also search the European (UCITS) versions; ISINs and UCITS queries search as typed
    precondition(searchQueries("Semiconductor") == ["Semiconductor", "Semiconductor UCITS"])
    precondition(searchQueries(" msci world ") == ["msci world", "msci world UCITS"])
    precondition(searchQueries("VanEck Semiconductor UCITS") == ["VanEck Semiconductor UCITS"])
    precondition(searchQueries("IE00BMC38736") == ["IE00BMC38736"])
    precondition(searchQueries("VVSM.DE") == ["VVSM.DE"])
}

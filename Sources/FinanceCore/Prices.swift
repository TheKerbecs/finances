import Foundation

public struct PriceError: Error, CustomStringConvertible {
    public var description: String
    init(_ s: String) { description = s }
}

public struct ChartQuote: Equatable, Sendable {
    public var price: Decimal
    public var currency: String
    public var closes: [Day: Decimal]
}

public struct SymbolHit: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public var symbol: String, exchange: String, name: String
    public init(symbol: String, exchange: String, name: String) { self.symbol = symbol; self.exchange = exchange; self.name = name }
}

/// JSON numbers arrive as Double, and Yahoo's are float32-noisy (129.92999267578125 for 129.93).
/// Four decimals is more than any EUR quote uses.
private func decimal(_ any: Any?) -> Decimal? {
    guard let n = any as? NSNumber, !(any is NSNull), let d = Decimal(string: String(n.doubleValue)) else { return nil }
    return roundTo(d, 4)
}

public func parseChart(_ data: Data) throws -> ChartQuote {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let chart = root["chart"] as? [String: Any],
          let result = (chart["result"] as? [[String: Any]])?.first,
          let meta = result["meta"] as? [String: Any],
          let price = decimal(meta["regularMarketPrice"]) else {
        throw PriceError("No price data in the response")
    }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: meta["exchangeTimezoneName"] as? String ?? "") ?? TimeZone(identifier: "Europe/Berlin")!
    var closes: [Day: Decimal] = [:]
    let stamps = result["timestamp"] as? [Any] ?? []
    let quote = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first
    let closeArr = quote?["close"] as? [Any] ?? []
    for (i, ts) in stamps.enumerated() where i < closeArr.count {
        guard let t = (ts as? NSNumber)?.doubleValue, let c = decimal(closeArr[i]) else { continue }
        closes[Day(Date(timeIntervalSince1970: t), cal)] = c
    }
    return ChartQuote(price: price, currency: meta["currency"] as? String ?? "", closes: closes)
}

public func parseSearch(_ data: Data) throws -> [SymbolHit] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let quotes = root["quotes"] as? [[String: Any]] else { throw PriceError("Unexpected search response") }
    return quotes.compactMap { q in
        guard let sym = q["symbol"] as? String else { return nil }
        return SymbolHit(symbol: sym, exchange: q["exchange"] as? String ?? "",
                         name: q["longname"] as? String ?? q["shortname"] as? String ?? sym)
    }
}

/// Close on `day`, or the nearest earlier one.
public func close(on day: Day, in closes: [Day: Decimal]) -> Decimal? {
    closes.filter { $0.key <= day }.max { $0.key < $1.key }?.value
}

/// Fills units of savings plan buys that are still at 0 from that day's close. Trades the user
/// corrected (unitsEstimated == false) are never touched.
@discardableResult
public func fillEstimatedUnits(_ d: inout FinanceData, closes: [UUID: [Day: Decimal]]) -> Int {
    var n = 0
    for i in d.trades.indices where d.trades[i].unitsEstimated && d.trades[i].units == 0 {
        let t = d.trades[i]
        guard let c = closes[t.holdingId], let price = close(on: t.date, in: c), price > 0 else { continue }
        d.trades[i].pricePerUnit = price
        d.trades[i].units = roundTo(t.amount / price, 6)
        n += 1
    }
    return n
}

public enum Yahoo {
    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw PriceError("Price server answered \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    /// from == nil: the last few days. Otherwise daily closes from that day to now.
    public static func chart(_ ticker: String, from: Day?) async throws -> ChartQuote {
        let t = ticker.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-_"))) ?? ticker
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(t)")!
        if let from {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let p1 = Int(utc.date(from: DateComponents(year: from.year, month: from.month, day: from.day))!.timeIntervalSince1970)
            c.queryItems = [.init(name: "period1", value: "\(p1)"), .init(name: "period2", value: "\(Int(Date().timeIntervalSince1970))"),
                            .init(name: "interval", value: "1d")]
        } else {
            c.queryItems = [.init(name: "range", value: "5d"), .init(name: "interval", value: "1d")]
        }
        return try parseChart(await get(c.url!))
    }

    public static func search(_ q: String) async throws -> [SymbolHit] {
        let queries = searchQueries(q)
        var hits = try await searchRaw(queries[0])
        for extra in queries.dropFirst() { hits += (try? await searchRaw(extra)) ?? [] }
        // An ISIN usually finds only one or two listings; searching the fund's name finds the EUR ones too.
        if looksLikeISIN(q), let name = hits.first?.name {
            hits += (try? await searchRaw(name)) ?? []
        }
        return rankHits(hits)
    }

    private static func searchRaw(_ q: String) async throws -> [SymbolHit] {
        var c = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        c.queryItems = [.init(name: "q", value: q), .init(name: "quotesCount", value: "15"), .init(name: "newsCount", value: "0")]
        return try parseSearch(await get(c.url!))
    }
}

/// Daily closes per ticker in <dir>/<TICKER>.json as {"2026-11-24": "120.5"}. Safe to delete.
public final class PriceCache {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    private func url(_ ticker: String) -> URL {
        directory.appendingPathComponent(ticker.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    public func load(_ ticker: String) -> [Day: Decimal] {
        guard let data = try? Data(contentsOf: url(ticker)),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var out: [Day: Decimal] = [:]
        for (k, v) in raw { if let d = Day(k), let p = Decimal(string: v) { out[d] = p } }
        return out
    }

    public func save(_ ticker: String, _ closes: [Day: Decimal]) {
        let raw = Dictionary(uniqueKeysWithValues: closes.map { ($0.key.description, "\($0.value)") })
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        try? enc.encode(raw).write(to: url(ticker), options: .atomic)
    }
}

/// Yahoo exchange codes that quote in EUR, best first (Xetra is where most German brokers' ETFs trade).
private let eurExchanges = ["GER", "FRA", "STU", "MUN", "HAM", "DUS", "BER", "AMS", "PAR", "MIL", "BRU", "MCE", "VIE", "LIS", "HEL", "ISE"]

private let exchangeNames = ["GER": "Xetra", "FRA": "Frankfurt", "STU": "Stuttgart", "MUN": "Munich", "HAM": "Hamburg",
                             "DUS": "Düsseldorf", "BER": "Berlin", "AMS": "Amsterdam", "PAR": "Paris", "MIL": "Milan",
                             "BRU": "Brussels", "MCE": "Madrid", "VIE": "Vienna", "LIS": "Lisbon", "HEL": "Helsinki",
                             "ISE": "Dublin", "LSE": "London", "EBS": "SIX Swiss", "NGM": "Nasdaq", "NMS": "Nasdaq",
                             "NYQ": "NYSE", "PCX": "NYSE Arca", "PNK": "OTC"]

public func exchangeName(_ code: String) -> String { exchangeNames[code] ?? code }

/// Whether a search result is quoted in EUR, judged by its exchange (confirmed on save).
public func isEURListing(_ h: SymbolHit) -> Bool { eurExchanges.contains(h.exchange) }

/// EUR listings first (Xetra on top), then the rest; duplicates removed.
public func rankHits(_ hits: [SymbolHit]) -> [SymbolHit] {
    var seen = Set<String>()
    let unique = hits.filter { seen.insert($0.symbol).inserted }
    let rank = { (h: SymbolHit) in eurExchanges.firstIndex(of: h.exchange) ?? eurExchanges.count }
    return unique.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
}

/// What to ask Yahoo for. Plain names also search "<name> UCITS": Yahoo shows US funds for generic
/// words, while European brokers sell the UCITS versions. Tickers, ISINs and UCITS queries go as typed.
public func searchQueries(_ q: String) -> [String] {
    let t = q.trimmingCharacters(in: .whitespaces)
    if looksLikeISIN(t) || t.lowercased().contains("ucits") || (t.contains(".") && !t.contains(" ")) { return [t] }
    return [t, t + " UCITS"]
}

/// "IE00BMC38736": two letters, nine letters/digits, one check digit.
public func looksLikeISIN(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces).uppercased()
    return t.count == 12 && t.prefix(2).allSatisfy(\.isLetter) && t.allSatisfy { $0.isLetter || $0.isNumber } && t.last!.isNumber
}

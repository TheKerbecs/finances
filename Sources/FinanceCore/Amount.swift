import Foundation

/// Parses a positive money amount typed as "12,50", "12.50", "1.234,56", "1,234.56", "1.000" or "7 €".
/// A lone separator followed by exactly three digits is a thousands separator ("1.000" = 1000).
/// Returns nil for anything else, including zero and negatives.
public func parseAmount(_ s: String) -> Decimal? { parse(s, money: true) }

/// Parses a positive unit count or price: one "," or "." is always the decimal separator ("125.825", "0,125").
public func parseNumber(_ s: String) -> Decimal? { parse(s, money: false) }

private func parse(_ s: String, money: Bool) -> Decimal? {
    var t = s.replacingOccurrences(of: "€", with: "").filter { !$0.isWhitespace }
    guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }) else { return nil }
    let commas = t.filter { $0 == "," }.count, dots = t.filter { $0 == "." }.count
    var decimalSep: Character?
    switch (commas, dots) {
    case (0, 0): decimalSep = nil
    case (_, 0) where !money: decimalSep = commas == 1 ? "," : nil
    case (0, _) where !money: decimalSep = dots == 1 ? "." : nil
    case (_, 0), (0, _):
        let sep: Character = commas > 0 ? "," : "."
        let digitsAfter = t.distance(from: t.lastIndex(of: sep)!, to: t.endIndex) - 1
        decimalSep = (commas + dots == 1 && digitsAfter != 3) ? sep : nil   // else thousands
        if decimalSep == nil {
            // every group after the first must be exactly 3 digits: "1.000.000" ok, "1,2,3" not
            let groups = t.split(separator: sep, omittingEmptySubsequences: false)
            guard groups.first.map({ !$0.isEmpty && $0.count <= 3 }) == true,
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
    default:
        decimalSep = t.lastIndex(of: ",")! > t.lastIndex(of: ".")! ? "," : "."
    }
    if let sep = decimalSep {
        t.removeAll { $0 == (sep == "," ? "." : ",") }
        guard t.filter({ $0 == sep }).count == 1 else { return nil }
        t = t.replacingOccurrences(of: String(sep), with: ".")
    } else {
        if !money && commas + dots > 0 { return nil }
        t.removeAll { $0 == "," || $0 == "." }
    }
    guard let v = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")), v > 0 else { return nil }
    return v
}

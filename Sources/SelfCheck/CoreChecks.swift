import Foundation
import FinanceCore

func runCoreChecks() {
    precondition(Day.clamped(year: 2026, month: 2, day: 31) == Day(year: 2026, month: 2, day: 28))
    precondition(Day.clamped(year: 2028, month: 2, day: 30) == Day(year: 2028, month: 2, day: 29))
    precondition(Day("2026-11-26") == Day(year: 2026, month: 11, day: 26))
    precondition(Day("2026-13-01") == nil)
    precondition(Day("2026-02-30") == nil)
    let enc = try! JSONEncoder().encode([Day(year: 2026, month: 1, day: 5)])
    precondition(String(data: enc, encoding: .utf8) == "[\"2026-01-05\"]")
    precondition(try! JSONDecoder().decode([Day].self, from: enc) == [Day(year: 2026, month: 1, day: 5)])
    precondition(Day(year: 2026, month: 12, day: 31).adding(days: 1) == Day(year: 2027, month: 1, day: 1))
    precondition(Day(year: 2026, month: 3, day: 1).adding(days: -1) == Day(year: 2026, month: 2, day: 28))
    precondition(YearMonth(year: 2026, month: 12).next == YearMonth(year: 2027, month: 1))
    precondition(YearMonth(year: 2026, month: 1).previous == YearMonth(year: 2025, month: 12))
    precondition(YearMonth(year: 2028, month: 2).dayCount == 29)
    precondition(Day(year: 2026, month: 5, day: 1) < Day(year: 2026, month: 5, day: 2))

    precondition(parseAmount("12,50") == Decimal(string: "12.50"))
    precondition(parseAmount("12.50") == Decimal(string: "12.50"))
    precondition(parseAmount("1.234,56") == Decimal(string: "1234.56"))
    precondition(parseAmount("1,234.56") == Decimal(string: "1234.56"))
    precondition(parseAmount(" 7 € ") == 7)
    precondition(parseAmount("abc") == nil && parseAmount("") == nil && parseAmount("-5") == nil && parseAmount("0") == nil)
    precondition(parseAmount("1.000") == 1000 && parseAmount("1,000") == 1000 && parseAmount("1.000,00") == 1000)
    precondition(parseNumber("125.825") == Decimal(string: "125.825") && parseNumber("0,125") == Decimal(string: "0.125"))
    precondition(parseNumber("3.319502") == Decimal(string: "3.319502") && parseNumber("x") == nil && parseNumber("0") == nil)
    precondition(parseAmount("12a") == nil && parseAmount("1,2,3") == nil)

    let d = FinanceData.defaults()
    precondition(d.categories.filter { $0.kind == .expense }.map(\.name) == ["Rent", "Groceries", "Eating out", "Transport", "Subscriptions", "Shopping", "Health", "Leisure", "Other"])
    precondition(d.categories.filter { $0.kind == .income }.map(\.name) == ["Salary", "Transfers", "Dividends", "Other"])
    let rt = try! JSONDecoder().decode(FinanceData.self, from: JSONEncoder().encode(d))
    precondition(rt == d)
}

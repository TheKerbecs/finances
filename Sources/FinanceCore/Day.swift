import Foundation

/// A calendar day with no time or time zone. Encoded as "yyyy-MM-dd".
public struct Day: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int, month: Int, day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    public init?(_ s: String) {
        let p = s.split(separator: "-").map { Int($0) }
        guard p.count == 3, let y = p[0], let m = p[1], let d = p[2],
              (1...12).contains(m), d >= 1, d <= YearMonth(year: y, month: m).dayCount else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(_ date: Date, _ cal: Calendar = .current) {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func today(_ cal: Calendar = .current) -> Day { Day(Date(), cal) }

    /// Day past the end of the month becomes the month's last day.
    public static func clamped(year: Int, month: Int, day: Int) -> Day {
        Day(year: year, month: month, day: min(day, YearMonth(year: year, month: month).dayCount))
    }

    public func date(_ cal: Calendar = .current) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days n: Int) -> Day {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let d = c.date(from: DateComponents(year: year, month: month, day: day))!
        return Day(c.date(byAdding: .day, value: n, to: d)!, c)
    }

    public var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let w = c.component(.weekday, from: c.date(from: DateComponents(year: year, month: month, day: day))!)   // 1 = Sunday
        return (w + 5) % 7 + 1
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: Day, b: Day) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = Day(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad day \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

public struct YearMonth: Codable, Hashable, Comparable, Sendable {
    public var year: Int, month: Int

    public init(year: Int, month: Int) { self.year = year; self.month = month }

    public var next: YearMonth { month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1) }
    public var previous: YearMonth { month == 1 ? YearMonth(year: year - 1, month: 12) : YearMonth(year: year, month: month - 1) }

    public var dayCount: Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    public func contains(_ d: Day) -> Bool { d.year == year && d.month == month }

    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

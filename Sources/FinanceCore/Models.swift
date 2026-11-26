import Foundation

public enum Kind: String, Codable, Sendable { case income, expense }
public enum Side: String, Codable, Sendable { case buy, sell }
public enum Frequency: String, Codable, Sendable { case weekly, monthly, quarterly, yearly }
public enum RuleTarget: String, Codable, Sendable { case transaction, trade, transfer }

public struct TxCategory: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: Kind
    public init(id: UUID = UUID(), name: String, kind: Kind) { self.id = id; self.name = name; self.kind = kind }
}

public struct Transaction: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Day
    public var amount: Decimal
    public var kind: Kind
    public var categoryId: UUID
    public var payee: String?
    public var note: String?
    public var recurringId: UUID?
    /// nil = the main account.
    public var accountId: UUID?
    public init(id: UUID = UUID(), date: Day, amount: Decimal, kind: Kind, categoryId: UUID,
                payee: String? = nil, note: String? = nil, recurringId: UUID? = nil, accountId: UUID? = nil) {
        self.id = id; self.date = date; self.amount = amount; self.kind = kind; self.categoryId = categoryId
        self.payee = payee; self.note = note; self.recurringId = recurringId; self.accountId = accountId
    }
}

public struct Holding: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var ticker: String
    public var lastPrice: Decimal?
    public var lastPriceDate: Day?
    public init(id: UUID = UUID(), name: String, ticker: String, lastPrice: Decimal? = nil, lastPriceDate: Day? = nil) {
        self.id = id; self.name = name; self.ticker = ticker; self.lastPrice = lastPrice; self.lastPriceDate = lastPriceDate
    }
}

public struct Trade: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var holdingId: UUID
    public var date: Day
    public var side: Side
    public var amount: Decimal
    public var units: Decimal
    public var pricePerUnit: Decimal
    public var note: String?
    public var recurringId: UUID?
    public var unitsEstimated: Bool
    /// The cash account that pays (or receives) the money; nil = the account savings plans are paid from.
    public var accountId: UUID?
    public init(id: UUID = UUID(), holdingId: UUID, date: Day, side: Side, amount: Decimal, units: Decimal,
                pricePerUnit: Decimal, note: String? = nil, recurringId: UUID? = nil, unitsEstimated: Bool = false, accountId: UUID? = nil) {
        self.id = id; self.holdingId = holdingId; self.date = date; self.side = side; self.amount = amount
        self.units = units; self.pricePerUnit = pricePerUnit; self.note = note; self.recurringId = recurringId
        self.unitsEstimated = unitsEstimated; self.accountId = accountId
    }
}

/// Weekly rules repeat every 7 days from `startDate`. Quarterly and yearly rules count months from `startDate.month`.
public struct RecurringRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var target: RuleTarget
    public var amount: Decimal
    public var frequency: Frequency
    public var dayOfMonth: Int
    public var startDate: Day
    public var endDate: Day?
    public var lastGenerated: Day?
    public var kind: Kind?
    public var categoryId: UUID?
    public var payee: String?
    public var holdingId: UUID?
    /// Account for transaction and savings-plan rules (nil = the default one).
    public var accountId: UUID?
    /// Transfer rules only.
    public var fromAccountId: UUID?
    public var toAccountId: UUID?
    public init(id: UUID = UUID(), target: RuleTarget, amount: Decimal, frequency: Frequency, dayOfMonth: Int,
                startDate: Day, endDate: Day? = nil, lastGenerated: Day? = nil, kind: Kind? = nil,
                categoryId: UUID? = nil, payee: String? = nil, holdingId: UUID? = nil, accountId: UUID? = nil,
                fromAccountId: UUID? = nil, toAccountId: UUID? = nil) {
        self.id = id; self.target = target; self.amount = amount; self.frequency = frequency
        self.dayOfMonth = dayOfMonth; self.startDate = startDate; self.endDate = endDate
        self.lastGenerated = lastGenerated; self.kind = kind; self.categoryId = categoryId
        self.payee = payee; self.holdingId = holdingId; self.accountId = accountId
        self.fromAccountId = fromAccountId; self.toAccountId = toAccountId
    }
}

/// Money moved between two of your accounts. Neither income nor spending.
public struct Transfer: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Day
    public var amount: Decimal
    public var from: UUID
    public var to: UUID
    public var note: String?
    public var recurringId: UUID?
    public init(id: UUID = UUID(), date: Day, amount: Decimal, from: UUID, to: UUID, note: String? = nil, recurringId: UUID? = nil) {
        self.id = id; self.date = date; self.amount = amount; self.from = from; self.to = to; self.note = note; self.recurringId = recurringId
    }
}

public struct FinanceData: Codable, Equatable, Sendable {
    public var version = 1
    public var categories: [TxCategory]
    public var transactions: [Transaction]
    public var holdings: [Holding]
    public var trades: [Trade]
    public var rules: [RecurringRule]
    public var accounts: [Account] = []
    public var transfers: [Transfer] = []

    public init(categories: [TxCategory] = [], transactions: [Transaction] = [], holdings: [Holding] = [],
                trades: [Trade] = [], rules: [RecurringRule] = [], accounts: [Account] = [], transfers: [Transfer] = []) {
        self.categories = categories; self.transactions = transactions; self.holdings = holdings
        self.trades = trades; self.rules = rules; self.accounts = accounts; self.transfers = transfers
    }

    private enum CodingKeys: String, CodingKey { case version, categories, transactions, holdings, trades, rules, accounts, transfers }

    /// Files written before a field existed still load (missing lists become empty).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try c.decode([TxCategory].self, forKey: .categories)
        transactions = try c.decode([Transaction].self, forKey: .transactions)
        holdings = try c.decode([Holding].self, forKey: .holdings)
        trades = try c.decode([Trade].self, forKey: .trades)
        rules = try c.decode([RecurringRule].self, forKey: .rules)
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        transfers = try c.decodeIfPresent([Transfer].self, forKey: .transfers) ?? []
    }

    public func account(_ id: UUID?) -> Account? { accounts.first { $0.id == id } }

    public static func defaults() -> FinanceData {
        let expense = ["Rent", "Groceries", "Eating out", "Transport", "Subscriptions", "Shopping", "Health", "Leisure", "Other"]
        let income = ["Salary", "Transfers", "Dividends", "Other"]
        return FinanceData(categories: expense.map { TxCategory(name: $0, kind: .expense) }
                                     + income.map { TxCategory(name: $0, kind: .income) })
    }

    public func category(_ id: UUID?) -> TxCategory? { categories.first { $0.id == id } }
    public func holding(_ id: UUID?) -> Holding? { holdings.first { $0.id == id } }
}

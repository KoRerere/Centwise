import Foundation

public enum LedgerError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// Money is integer fen, never a binary floating-point value.
public enum Money {
    public static let maximum: Int64 = 9_000_000_000_000
    public static func parse(_ text: String) throws -> Int64 {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^-?[0-9]+(?:\.[0-9]{1,2})?$"#
        guard normalized.range(of: pattern, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else {
            throw LedgerError.invalid("请输入金额，最多保留两位小数，不要使用千位分隔符。")
        }
        return try cents(decimal)
    }

    /// SQLite REAL is read as text first; tolerate only representation noise below 1/10000 fen.
    public static func legacy(_ text: String) throws -> Int64 {
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw LedgerError.invalid("旧账本含有无法识别的金额。")
        }
        return try cents(decimal, allowStorageNoise: true)
    }

    private static func cents(_ decimal: Decimal, allowStorageNoise: Bool = false) throws -> Int64 {
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let difference = abs(scaled - rounded)
        guard !scaled.isNaN, abs(rounded) <= Decimal(maximum),
              difference <= (allowStorageNoise ? Decimal(string: "0.0001")! : 0) else {
            throw LedgerError.invalid("金额超出范围，或含有超过两位小数的有效精度。")
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    public static func text(_ cents: Int64, symbol: Bool = true) -> String {
        let value = Decimal(cents) / 100
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = symbol ? .currency : .decimal
        formatter.currencyCode = "CNY"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    public static func input(_ cents: Int64) -> String {
        let number = NSDecimalNumber(decimal: Decimal(cents) / 100)
        return number.stringValue
    }
}

public enum EntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case expense, income, transfer, adjustment
    public var id: String { rawValue }
    public var title: String {
        switch self { case .expense: "支出"; case .income: "收入"; case .transfer: "转账"; case .adjustment: "余额调整" }
    }
    public var symbol: String {
        switch self { case .expense: "arrow.up.right"; case .income: "arrow.down.left"; case .transfer: "arrow.left.arrow.right"; case .adjustment: "equal.circle" }
    }
}

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var openingBalance: Int64
    public var currency: String = "CNY"
    public var archived: Bool = false
    public init(id: String = UUID().uuidString, name: String, openingBalance: Int64 = 0, archived: Bool = false) {
        self.id = id; self.name = name; self.openingBalance = openingBalance; self.archived = archived
    }
}

public struct LedgerCategory: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: EntryKind
    public var symbol: String
    public var parentID: String?
    public init(id: String = UUID().uuidString, name: String, kind: EntryKind, symbol: String = "square.grid.2x2", parentID: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.symbol = symbol; self.parentID = parentID
    }
}

public struct Allocation: Codable, Equatable, Sendable {
    public var categoryID: String
    public var amount: Int64
    public init(categoryID: String, amount: Int64) { self.categoryID = categoryID; self.amount = amount }
}

public struct Entry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: EntryKind
    public var amount: Int64
    public var date: Date
    public var accountID: String
    public var destinationID: String?
    public var allocations: [Allocation]
    public var note: String
    public var payee: String
    public var pending: Bool = false
    public var legacyType: Int?
    public var needsReview: Bool = false
    public init(id: String = UUID().uuidString, kind: EntryKind, amount: Int64, date: Date = .now,
                accountID: String, destinationID: String? = nil, allocations: [Allocation] = [],
                note: String = "", payee: String = "", pending: Bool = false, legacyType: Int? = nil, needsReview: Bool = false) {
        self.id = id; self.kind = kind; self.amount = amount; self.date = date; self.accountID = accountID
        self.destinationID = destinationID; self.allocations = allocations; self.note = note; self.payee = payee
        self.pending = pending; self.legacyType = legacyType; self.needsReview = needsReview
    }
}

public struct Budget: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var categoryID: String?
    public var limit: Int64
    public init(id: String = UUID().uuidString, categoryID: String? = nil, limit: Int64) {
        self.id = id; self.categoryID = categoryID; self.limit = limit
    }
}

public struct LegacyArchive: Codable, Equatable, Sendable {
    public var importedAt: Date
    public var tables: [String: [[String: String?]]]
    public var warnings: [String]
    public init(tables: [String: [[String: String?]]], warnings: [String]) {
        self.importedAt = .now; self.tables = tables; self.warnings = warnings
    }
}

public struct Ledger: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var title: String = "我的账本"
    public var accounts: [Account]
    public var categories: [LedgerCategory]
    public var entries: [Entry]
    public var budgets: [Budget]
    public var legacy: LegacyArchive?
    public init(title: String = "我的账本", accounts: [Account] = [], categories: [LedgerCategory] = [],
                entries: [Entry] = [], budgets: [Budget] = [], legacy: LegacyArchive? = nil) {
        self.title = title; self.accounts = accounts; self.categories = categories; self.entries = entries
        self.budgets = budgets; self.legacy = legacy
    }

    public static func empty() -> Ledger {
        Ledger(accounts: [Account(id: "cash", name: "日常账户")], categories: [
            LedgerCategory(id: "food", name: "餐饮", kind: .expense, symbol: "fork.knife"),
            LedgerCategory(id: "transport", name: "交通", kind: .expense, symbol: "tram.fill"),
            LedgerCategory(id: "shopping", name: "购物", kind: .expense, symbol: "bag.fill"),
            LedgerCategory(id: "home", name: "居家", kind: .expense, symbol: "house.fill"),
            LedgerCategory(id: "fun", name: "休闲", kind: .expense, symbol: "sparkles"),
            LedgerCategory(id: "other", name: "其他", kind: .expense, symbol: "ellipsis.circle"),
            LedgerCategory(id: "salary", name: "工资", kind: .income, symbol: "briefcase.fill"),
            LedgerCategory(id: "bonus", name: "其他收入", kind: .income, symbol: "gift.fill")
        ])
    }

    public static func demo(now: Date = .now) -> Ledger {
        var ledger = empty()
        ledger.title = "演示账本 · 非真实数据"
        ledger.accounts[0].openingBalance = 320_000
        ledger.accounts.append(Account(id: "bank", name: "储蓄账户", openingBalance: 2_400_000))
        ledger.budgets = [Budget(limit: 600_000), Budget(categoryID: "food", limit: 150_000)]
        let calendar = Calendar(identifier: .gregorian)
        let beginning = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let data: [(Int, String, Int64, String)] = [(0,"salary",1_280_000,"月度工资"),(1,"food",3_600,"周末早餐"),
            (2,"transport",2_800,"通勤打车"),(3,"shopping",25_900,"换季衣物"),(4,"food",12_600,"和朋友吃晚饭"),
            (5,"home",18_900,"生活用品"),(6,"fun",6_800,"看一场电影"),(7,"food",2_800,"咖啡与面包")]
        ledger.entries = data.map { day, category, amount, note in
            Entry(kind: category == "salary" ? .income : .expense, amount: amount,
                  date: calendar.date(byAdding: .day, value: day, to: beginning) ?? now,
                  accountID: category == "salary" ? "bank" : "cash",
                  allocations: [Allocation(categoryID: category, amount: amount)], note: note)
        }
        return ledger
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw LedgerError.invalid("不支持此备份版本，不能覆盖现有账本。") }
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, title.count <= 100,
              entries.count <= 100_000, accounts.count <= 500, categories.count <= 5_000, budgets.count <= 500 else {
            throw LedgerError.invalid("账本名称或记录数量超出范围。")
        }
        func unique(_ ids: [String], _ label: String) throws {
            guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
                throw LedgerError.invalid("\(label)含重复或空编号。")
            }
        }
        try unique(accounts.map(\.id), "账户"); try unique(categories.map(\.id), "分类")
        try unique(entries.map(\.id), "记录"); try unique(budgets.map(\.id), "预算")
        let accountIDs = Set(accounts.map(\.id)), categoryIDs = Set(categories.map(\.id))
        for account in accounts {
            guard account.currency == "CNY", !account.name.isEmpty, account.name.count <= 200,
                  (-Money.maximum...Money.maximum).contains(account.openingBalance) else {
                throw LedgerError.invalid("第一版只支持人民币；请检查账户名称和期初余额。")
            }
        }
        let categoryKinds = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.kind) })
        for category in categories {
            guard !category.name.isEmpty, category.name.count <= 200, [.expense, .income].contains(category.kind),
                  category.parentID == nil || categoryIDs.contains(category.parentID!), category.parentID != category.id else {
                throw LedgerError.invalid("分类名称、类型或父分类无效。")
            }
        }
        for entry in entries {
            let seconds = entry.date.timeIntervalSince1970
            guard seconds.isFinite, (0...4_102_444_800).contains(seconds), accountIDs.contains(entry.accountID),
                  (-Money.maximum...Money.maximum).contains(entry.amount), entry.note.count <= 10_000, entry.payee.count <= 1_000 else {
                throw LedgerError.invalid("记录含无效日期、金额或账户。")
            }
            if entry.kind == .transfer {
                guard entry.amount > 0, let destination = entry.destinationID,
                      accountIDs.contains(destination), destination != entry.accountID, entry.allocations.isEmpty else {
                    throw LedgerError.invalid("转账必须有不同的转出/转入账户、正数金额，且不能参与收支分类。")
                }
            } else if entry.destinationID != nil {
                throw LedgerError.invalid("非转账记录不能有转入账户。")
            }
            if entry.kind == .adjustment && !entry.allocations.isEmpty {
                throw LedgerError.invalid("余额调整不能计入分类收支。")
            }
            if [.income, .expense].contains(entry.kind) {
                guard !entry.allocations.isEmpty, entry.allocations.count <= 100,
                      entry.allocations.allSatisfy({ categoryKinds[$0.categoryID] == entry.kind && (-Money.maximum...Money.maximum).contains($0.amount) }),
                      entry.allocations.reduce(Int64(0), { $0 + abs($1.amount) }) <= Money.maximum,
                      entry.allocations.reduce(Int64(0), { $0 + $1.amount }) == entry.amount else {
                    throw LedgerError.invalid("分类分摊金额必须与该笔收支一致。")
                }
            }
        }
        var targets = Set<String>()
        for budget in budgets {
            let target = budget.categoryID ?? "__all__"
            guard budget.limit > 0, budget.limit <= Money.maximum, targets.insert(target).inserted,
                  budget.categoryID == nil || categoryKinds[budget.categoryID!] == .expense else {
                throw LedgerError.invalid("每个支出分类只能有一个正数月预算。")
            }
        }
    }

    public func balance(of accountID: String) -> Int64 {
        let initial = accounts.first(where: { $0.id == accountID })?.openingBalance ?? 0
        return entries.filter { !$0.pending }.reduce(initial) { value, entry in
            var delta: Int64 = 0
            if entry.accountID == accountID { delta = entry.kind == .expense || entry.kind == .transfer ? -entry.amount : entry.amount }
            if entry.kind == .transfer && entry.destinationID == accountID { delta += entry.amount }
            return value + delta
        }
    }

    public func monthEntries(_ month: Date, calendar: Calendar = .current) -> [Entry] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        return entries.filter { !$0.pending && $0.date >= interval.start && $0.date < interval.end }
    }

    public func total(_ kind: EntryKind, month: Date) -> Int64 {
        monthEntries(month).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
    }

    public func categorySpending(month: Date) -> [(category: LedgerCategory, amount: Int64)] {
        var values: [String: Int64] = [:]
        for entry in monthEntries(month) where entry.kind == .expense {
            for allocation in entry.allocations { values[allocation.categoryID, default: 0] += allocation.amount }
        }
        return categories.filter { $0.kind == .expense }.map { ($0, values[$0.id] ?? 0) }
            .filter { $0.1 != 0 }.sorted { $0.1 > $1.1 }
    }

    public func spent(_ budget: Budget, month: Date) -> Int64 {
        guard let category = budget.categoryID else { return total(.expense, month: month) }
        return monthEntries(month).filter { $0.kind == .expense }.flatMap(\.allocations)
            .filter { $0.categoryID == category }.reduce(0) { $0 + $1.amount }
    }
}

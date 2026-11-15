import Foundation

// MARK: JSON helpers (backup format compatible with the Flutter and old SwiftUI versions)

typealias JSON = [String: Any]

private func jInt(_ value: Any?, _ fallback: Int = 0) throws -> Int {
    guard let value, !(value is NSNull) else { return fallback }
    if let n = value as? NSNumber {
        // Booleans are NSNumber too; reject them.
        if CFGetTypeID(n) == CFBooleanGetTypeID() { throw LedgerError(tr("备份中的数字字段无效。")) }
        let d = n.doubleValue
        if d.rounded() == d, abs(d) < 9.3e18 { return n.int64Value == Int64(d) ? Int(n.int64Value) : Int(d) }
    }
    throw LedgerError(tr("备份中的数字字段无效。"))
}

private func jString(_ value: Any?, _ fallback: String = "") -> String { value as? String ?? fallback }
private func jOptString(_ value: Any?) -> String? { value as? String }
private func jBool(_ value: Any?, _ fallback: Bool = false) -> Bool {
    if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
    return fallback
}
private func jList(_ value: Any?) -> [JSON] { (value as? [Any] ?? []).compactMap { $0 as? JSON } }

/// Foundation's `Date` Codable form: seconds since 2001-01-01 00:00:00 UTC.
func encodeDate(_ d: Date) -> Double { d.timeIntervalSinceReferenceDate }

func decodeDate(_ value: Any?) throws -> Date {
    guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else {
        throw LedgerError(tr("记录含无效日期、金额或账户。"))
    }
    return Date(timeIntervalSinceReferenceDate: n.doubleValue)
}

/// Random UUID in Foundation's uppercase form.
func newID() -> String { UUID().uuidString }

// MARK: Model

enum EntryKind: String, CaseIterable, Hashable {
    case expense, income, transfer, adjustment

    var title: String {
        switch self {
        case .expense: tr("支出")
        case .income: tr("收入")
        case .transfer: tr("转账")
        case .adjustment: tr("余额调整")
        }
    }

    static func parse(_ raw: Any?) throws -> EntryKind {
        guard let s = raw as? String, let kind = EntryKind(rawValue: s) else { throw LedgerError(tr("备份中有未知的记录类型。")) }
        return kind
    }

    var isFlow: Bool { self == .income || self == .expense }
}

struct Account: Identifiable, Hashable {
    var id: String = newID()
    var name: String
    var openingBalance: Int = 0
    var currency: String = "CNY"
    var archived: Bool = false

    var json: JSON { ["archived": archived, "currency": currency, "id": id, "name": name, "openingBalance": openingBalance] }

    init(id: String = newID(), name: String, openingBalance: Int = 0, currency: String = "CNY", archived: Bool = false) {
        self.id = id; self.name = name; self.openingBalance = openingBalance; self.currency = currency; self.archived = archived
    }

    init(json: JSON) throws {
        id = jString(json["id"]); name = jString(json["name"])
        openingBalance = try jInt(json["openingBalance"])
        currency = jString(json["currency"], "CNY"); archived = jBool(json["archived"])
    }
}

struct LedgerCategory: Identifiable, Hashable {
    var id: String = newID()
    var name: String
    var kind: EntryKind
    /// A Lucide icon name or an emoji; old backups carry SF Symbol names (mapped when drawing).
    var symbol: String = "layout-grid"
    var parentID: String?

    init(id: String = newID(), name: String, kind: EntryKind, symbol: String = "layout-grid", parentID: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.symbol = symbol; self.parentID = parentID
    }

    var json: JSON {
        var j: JSON = ["id": id, "kind": kind.rawValue, "name": name, "symbol": symbol]
        if let parentID { j["parentID"] = parentID }
        return j
    }

    init(json: JSON) throws {
        id = jString(json["id"]); name = jString(json["name"])
        kind = try EntryKind.parse(json["kind"])
        symbol = jString(json["symbol"], "layout-grid")
        parentID = jOptString(json["parentID"])
    }
}

struct Allocation: Hashable {
    var categoryID: String
    var amount: Int
    var json: JSON { ["amount": amount, "categoryID": categoryID] }
    init(categoryID: String, amount: Int) { self.categoryID = categoryID; self.amount = amount }
    init(json: JSON) throws { categoryID = jString(json["categoryID"]); amount = try jInt(json["amount"]) }
}

struct Entry: Identifiable, Hashable {
    var id: String = newID()
    var kind: EntryKind
    var amount: Int
    var date: Date = Date()
    var accountID: String
    var destinationID: String?
    var allocations: [Allocation] = []
    var note: String = ""
    var payee: String = ""
    var pending: Bool = false
    var legacyType: Int?
    var needsReview: Bool = false

    init(id: String = newID(), kind: EntryKind, amount: Int, date: Date = Date(), accountID: String, destinationID: String? = nil,
         allocations: [Allocation] = [], note: String = "", payee: String = "", pending: Bool = false, legacyType: Int? = nil,
         needsReview: Bool = false) {
        self.id = id; self.kind = kind; self.amount = amount; self.date = date; self.accountID = accountID
        self.destinationID = destinationID; self.allocations = allocations; self.note = note; self.payee = payee
        self.pending = pending; self.legacyType = legacyType; self.needsReview = needsReview
    }

    var json: JSON {
        var j: JSON = [
            "accountID": accountID, "allocations": allocations.map(\.json), "amount": amount, "date": encodeDate(date),
            "id": id, "kind": kind.rawValue, "needsReview": needsReview, "note": note, "payee": payee, "pending": pending,
        ]
        if let destinationID { j["destinationID"] = destinationID }
        if let legacyType { j["legacyType"] = legacyType }
        return j
    }

    init(json: JSON) throws {
        id = jString(json["id"]); kind = try EntryKind.parse(json["kind"]); amount = try jInt(json["amount"])
        date = try decodeDate(json["date"]); accountID = jString(json["accountID"])
        destinationID = jOptString(json["destinationID"])
        allocations = try jList(json["allocations"]).map(Allocation.init(json:))
        note = jString(json["note"]); payee = jString(json["payee"]); pending = jBool(json["pending"])
        legacyType = json["legacyType"] == nil || json["legacyType"] is NSNull ? nil : try jInt(json["legacyType"])
        needsReview = jBool(json["needsReview"])
    }
}

/// A calendar month without a day, e.g. a 本月预算's month.
struct YearMonth: Hashable, Comparable {
    var year: Int
    var month: Int
    init(_ year: Int, _ month: Int) { self.year = year; self.month = month }
    init(_ date: Date) { let p = Cal.parts(date); year = p.year; month = p.month }
    var date: Date { Cal.date(year, month, 1) }
    static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
}

struct Budget: Identifiable, Hashable {
    var id: String = newID()
    var categoryID: String?
    var limit: Int
    /// nil: 每月预算, applies to every month. Otherwise 本月预算 for only that month.
    var month: YearMonth?

    init(id: String = newID(), categoryID: String? = nil, limit: Int, month: YearMonth? = nil) {
        self.id = id; self.categoryID = categoryID; self.limit = limit; self.month = month
    }

    func applies(to m: YearMonth) -> Bool { month == nil || month == m }

    var json: JSON {
        var j: JSON = ["id": id, "limit": limit]
        if let categoryID { j["categoryID"] = categoryID }
        if let month { j["month"] = String(format: "%d-%02d", month.year, month.month) }
        return j
    }

    init(json: JSON) throws {
        id = jString(json["id"]); categoryID = jOptString(json["categoryID"]); limit = try jInt(json["limit"])
        if let s = json["month"] as? String {
            let parts = s.split(separator: "-").map { Int($0) }
            guard parts.count == 2, let y = parts[0], let m = parts[1], (1...12).contains(m) else {
                throw LedgerError(tr("备份中的数字字段无效。"))
            }
            month = YearMonth(y, m)
        } else {
            month = nil
        }
    }
}

/// How often a subscription charges.
enum BillingCycle: String, CaseIterable, Hashable {
    case monthly, quarterly, yearly

    var months: Int {
        switch self { case .monthly: 1; case .quarterly: 3; case .yearly: 12 }
    }

    var title: String {
        switch self { case .monthly: tr("月付"); case .quarterly: tr("季付"); case .yearly: tr("年付") }
    }

    static func parse(_ raw: Any?) throws -> BillingCycle {
        guard let s = raw as? String, let c = BillingCycle(rawValue: s) else { throw LedgerError(tr("备份中有未知的扣费周期。")) }
        return c
    }
}

/// A recurring charge. Only a confirmed charge becomes an expense entry; `nextDate` is the next charge
/// still to be confirmed, `charged` remembers every day already booked so a cycle is never booked twice.
struct Subscription: Identifiable, Hashable {
    var id: String = newID()
    var name: String
    var amount: Int
    var cycle: BillingCycle = .monthly
    var nextDate: Date
    var categoryID: String?
    var note: String = ""
    var cancelled: Bool = false
    var cancelledAt: Date?
    /// The day of the month it charges on (kept apart so the 31st survives short months).
    var anchorDay: Int
    var charged: [String] = []

    init(id: String = newID(), name: String, amount: Int, cycle: BillingCycle = .monthly, nextDate: Date, categoryID: String? = nil,
         note: String = "", cancelled: Bool = false, cancelledAt: Date? = nil, anchorDay: Int? = nil, charged: [String] = []) {
        self.id = id; self.name = name; self.amount = amount; self.cycle = cycle
        self.nextDate = Cal.dateOnly(nextDate)
        self.categoryID = categoryID; self.note = note; self.cancelled = cancelled; self.cancelledAt = cancelledAt
        self.anchorDay = anchorDay ?? Cal.day(nextDate)
        self.charged = charged
    }

    /// `date` moved by `months`, on `anchorDay` or the month's last day when it is shorter.
    static func addMonths(_ date: Date, _ months: Int, _ anchorDay: Int) -> Date {
        let p = Cal.parts(date)
        let first = Cal.date(p.year, p.month + months, 1)
        let last = Cal.daysInMonth(first)
        let fp = Cal.parts(first)
        return Cal.date(fp.year, fp.month, min(anchorDay, last))
    }

    func after(_ date: Date) -> Date { Subscription.addMonths(date, cycle.months, anchorDay) }

    func isDue(_ today: Date) -> Bool { !cancelled && nextDate <= Cal.dateOnly(today) }

    /// Cost per month in hundredths of a cent, so a sum of several plans rounds only once.
    var monthlyMicro: Int { amount * 100 / cycle.months }

    /// Planned charge days in [start, end), from nextDate on.
    func planned(in start: Date, _ end: Date) -> [Date] {
        var days: [Date] = []
        if cancelled { return days }
        var day = nextDate
        var guardCount = 0
        while guardCount < 400 && day < end {
            if day >= start { days.append(day) }
            day = after(day)
            guardCount += 1
        }
        return days
    }

    var json: JSON {
        var j: JSON = [
            "amount": amount, "anchorDay": anchorDay, "cancelled": cancelled, "charged": charged, "cycle": cycle.rawValue,
            "id": id, "name": name, "nextDate": dayKey(nextDate), "note": note,
        ]
        if let cancelledAt { j["cancelledAt"] = encodeDate(cancelledAt) }
        if let categoryID { j["categoryID"] = categoryID }
        return j
    }

    init(json: JSON) throws {
        id = jString(json["id"]); name = jString(json["name"]); amount = try jInt(json["amount"])
        cycle = try BillingCycle.parse(json["cycle"])
        nextDate = try parseDayKey(json["nextDate"])
        categoryID = jOptString(json["categoryID"]); note = jString(json["note"]); cancelled = jBool(json["cancelled"])
        cancelledAt = json["cancelledAt"] == nil || json["cancelledAt"] is NSNull ? nil : try decodeDate(json["cancelledAt"])
        anchorDay = json["anchorDay"] == nil || json["anchorDay"] is NSNull ? Cal.day(nextDate) : try jInt(json["anchorDay"])
        charged = (json["charged"] as? [Any] ?? []).compactMap { $0 as? String }
    }
}

/// Original Money Pro tables kept verbatim (values as text, NULL as nil). Read-only; kept as raw JSON.
struct LegacyArchive {
    var importedAt: Date
    /// tables: name → rows (column → text or NSNull), stored exactly as read.
    var tables: [String: Any]
    var warnings: [String]

    var json: JSON { ["importedAt": encodeDate(importedAt), "tables": tables, "warnings": warnings] }

    init(importedAt: Date = Date(), tables: [String: Any], warnings: [String]) {
        self.importedAt = importedAt; self.tables = tables; self.warnings = warnings
    }

    init(json: JSON) throws {
        importedAt = try decodeDate(json["importedAt"])
        tables = json["tables"] as? [String: Any] ?? [:]
        warnings = (json["warnings"] as? [Any] ?? []).compactMap { $0 as? String }
    }
}

struct Ledger {
    var schemaVersion = 1
    var title = "我的账本"
    /// Kept for old entries and backups. New bills go to the first active one (hidden default account).
    var accounts: [Account] = []
    var categories: [LedgerCategory] = []
    var entries: [Entry] = []
    var budgets: [Budget] = []
    /// Written only when there are some, so ledgers without subscriptions stay byte-compatible.
    var subscriptions: [Subscription] = []
    var legacy: LegacyArchive?

    var json: JSON {
        var j: JSON = [
            "accounts": accounts.map(\.json), "budgets": budgets.map(\.json), "categories": categories.map(\.json),
            "entries": entries.map(\.json), "schemaVersion": schemaVersion, "title": title,
        ]
        if let legacy { j["legacy"] = legacy.json }
        if !subscriptions.isEmpty { j["subscriptions"] = subscriptions.map(\.json) }
        return j
    }

    init() {}

    init(json: JSON) throws {
        schemaVersion = try jInt(json["schemaVersion"], 1)
        title = jString(json["title"], "我的账本")
        accounts = try jList(json["accounts"]).map(Account.init(json:))
        categories = try jList(json["categories"]).map(LedgerCategory.init(json:))
        entries = try jList(json["entries"]).map(Entry.init(json:))
        budgets = try jList(json["budgets"]).map(Budget.init(json:))
        subscriptions = try jList(json["subscriptions"]).map(Subscription.init(json:))
        if let l = json["legacy"] as? JSON { legacy = try LegacyArchive(json: l) }
    }

    static func empty() -> Ledger {
        var l = Ledger()
        l.accounts = [Account(id: "cash", name: tr("日常账户"))]
        l.categories = [
            LedgerCategory(id: "food", name: tr("餐饮"), kind: .expense, symbol: "utensils"),
            LedgerCategory(id: "transport", name: tr("交通"), kind: .expense, symbol: "train-front"),
            LedgerCategory(id: "shopping", name: tr("购物"), kind: .expense, symbol: "shopping-bag"),
            LedgerCategory(id: "home", name: tr("居家"), kind: .expense, symbol: "house"),
            LedgerCategory(id: "fun", name: tr("休闲"), kind: .expense, symbol: "sparkles"),
            LedgerCategory(id: "other", name: tr("其他"), kind: .expense, symbol: "ellipsis"),
            LedgerCategory(id: "salary", name: tr("工资"), kind: .income, symbol: "briefcase"),
            LedgerCategory(id: "bonus", name: tr("其他收入"), kind: .income, symbol: "gift"),
        ]
        return l
    }

    static func demo(now: Date = Date()) -> Ledger {
        var ledger = empty()
        ledger.title = tr("演示账本 · 非真实数据")
        ledger.accounts[0].openingBalance = 320000
        ledger.accounts.append(Account(id: "bank", name: tr("储蓄账户"), openingBalance: 2_400_000))
        ledger.budgets = [Budget(limit: 600000), Budget(categoryID: "food", limit: 150000)]
        let p = Cal.parts(now)
        let data: [(Int, String, Int, String)] = [
            (0, "salary", 1_280_000, tr("月度工资")), (1, "food", 3600, tr("周末早餐")), (2, "transport", 2800, tr("通勤打车")),
            (3, "shopping", 25900, tr("换季衣物")), (4, "food", 12600, tr("和朋友吃晚饭")), (5, "home", 18900, tr("生活用品")),
            (6, "fun", 6800, tr("看一场电影")), (7, "food", 2800, tr("咖啡与面包")),
        ]
        ledger.entries = data.map { day, category, amount, note in
            Entry(kind: category == "salary" ? .income : .expense, amount: amount, date: Cal.date(p.year, p.month, 1 + day, 12),
                  accountID: category == "salary" ? "bank" : "cash", allocations: [Allocation(categoryID: category, amount: amount)], note: note)
        }
        ledger.entries.append(Entry(kind: .expense, amount: 3200, date: Cal.date(p.year, p.month, p.day, 8, 30), accountID: "cash",
                                    allocations: [Allocation(categoryID: "food", amount: 3200)], note: tr("早餐")))
        ledger.entries.append(Entry(kind: .expense, amount: 600, date: Cal.date(p.year, p.month, p.day, 9, 10), accountID: "cash",
                                    allocations: [Allocation(categoryID: "transport", amount: 600)], note: tr("地铁")))
        ledger.subscriptions = [
            Subscription(name: tr("视频会员"), amount: 2500, nextDate: Cal.date(p.year, p.month, p.day + 5), categoryID: "fun"),
            Subscription(name: tr("音乐会员"), amount: 1500, nextDate: Cal.date(p.year, p.month, p.day), categoryID: "fun"),
            Subscription(name: tr("云存储"), amount: 6800, cycle: .quarterly, nextDate: Cal.date(p.year, p.month, p.day + 12), categoryID: "home"),
            Subscription(name: tr("域名续费"), amount: 6900, cycle: .yearly, nextDate: Cal.date(p.year, p.month + 4, 1), categoryID: "other"),
        ]
        return ledger
    }

    func validate() throws {
        if schemaVersion != 1 { throw LedgerError(tr("不支持此备份版本，不能覆盖现有账本。")) }
        if title.trimmingCharacters(in: .whitespaces).isEmpty || title.count > 100 || entries.count > 100_000 || accounts.count > 500
            || categories.count > 5000 || budgets.count > 500 || subscriptions.count > 500 {
            throw LedgerError(tr("账本名称或记录数量超出范围。"))
        }
        func unique(_ ids: [String], _ label: String) throws {
            if ids.contains(where: \.isEmpty) || Set(ids).count != ids.count {
                throw LedgerError(tr("{label}含重复或空编号。", ["label": label]))
            }
        }
        try unique(accounts.map(\.id), tr("账户"))
        try unique(categories.map(\.id), tr("分类"))
        try unique(entries.map(\.id), tr("记录"))
        try unique(budgets.map(\.id), tr("预算"))
        let accountIDs = Set(accounts.map(\.id))
        let categoryIDs = Set(categories.map(\.id))
        func inRange(_ v: Int) -> Bool { v >= -Money.maximum && v <= Money.maximum }
        for a in accounts where !isSupportedCurrency(a.currency) || a.name.isEmpty || a.name.count > 200 || !inRange(a.openingBalance) {
            throw LedgerError(tr("请检查账户币种、名称和期初余额。"))
        }
        if Set(accounts.map(\.currency)).count > 1 { throw LedgerError(tr("一本账的账户只能使用同一种币种。")) }
        var kinds: [String: EntryKind] = [:]
        for c in categories { kinds[c.id] = c.kind }
        for c in categories {
            if c.name.isEmpty || c.name.count > 200 || !c.kind.isFlow || (c.parentID != nil && !categoryIDs.contains(c.parentID!)) || c.parentID == c.id {
                throw LedgerError(tr("分类名称、类型或父分类无效。"))
            }
        }
        for e in entries {
            let seconds = e.date.timeIntervalSince1970
            if seconds < 0 || seconds > 4_102_444_800 || !accountIDs.contains(e.accountID) || !inRange(e.amount) || e.note.count > 10000 || e.payee.count > 1000 {
                throw LedgerError(tr("记录含无效日期、金额或账户。"))
            }
            if e.kind == .transfer {
                if e.amount <= 0 || e.destinationID == nil || !accountIDs.contains(e.destinationID!) || e.destinationID == e.accountID || !e.allocations.isEmpty {
                    throw LedgerError(tr("转账必须有不同的转出/转入账户、正数金额，且不能参与收支分类。"))
                }
            } else if e.destinationID != nil {
                throw LedgerError(tr("非转账记录不能有转入账户。"))
            }
            if e.kind == .adjustment && !e.allocations.isEmpty { throw LedgerError(tr("余额调整不能计入分类收支。")) }
            if e.kind.isFlow {
                let absolute = e.allocations.reduce(0) { $0 + abs($1.amount) }
                let total = e.allocations.reduce(0) { $0 + $1.amount }
                if e.allocations.isEmpty || e.allocations.count > 100 || !e.allocations.allSatisfy({ kinds[$0.categoryID] == e.kind && inRange($0.amount) })
                    || absolute > Money.maximum || total != e.amount {
                    throw LedgerError(tr("分类分摊金额必须与该笔收支一致。"))
                }
            }
        }
        var targets = Set<String>()
        for b in budgets {
            let target = "\(b.categoryID ?? "__all__")@\(b.month.map { "\($0.year)-\($0.month)" } ?? "every")"
            if b.limit <= 0 || b.limit > Money.maximum || !targets.insert(target).inserted || (b.categoryID != nil && kinds[b.categoryID!] != .expense) {
                throw LedgerError(tr("同一范围只能有一个每月预算，同一个月也只能有一个本月预算，金额需大于零。"))
            }
        }
        try unique(subscriptions.map(\.id), tr("订阅"))
        for s in subscriptions {
            if s.name.trimmingCharacters(in: .whitespaces).isEmpty || s.name.count > 200 || s.note.count > 10000 || s.amount <= 0
                || s.amount > Money.maximum || s.anchorDay < 1 || s.anchorDay > 31 || s.charged.count > 5000 {
                throw LedgerError(tr("订阅需要名称和大于零的金额。"))
            }
        }
    }

    // MARK: Subscriptions

    var activeSubscriptions: [Subscription] { subscriptions.filter { !$0.cancelled } }

    /// 月均固定费用: monthly as is, quarterly ÷ 3, yearly ÷ 12, summed then rounded to the cent.
    var subscriptionMonthlyAverage: Int {
        let micro = activeSubscriptions.reduce(0) { $0 + $1.monthlyMicro }
        return Int((Double(micro) / 100).rounded())
    }

    /// 本月预计扣费: confirmed charges this month plus the ones still to come.
    func subscriptionCharges(in month: Date) -> Int {
        let p = Cal.parts(month)
        let start = Cal.date(p.year, p.month, 1), end = Cal.date(p.year, p.month + 1, 1)
        let lo = dayKey(start), hi = dayKey(end)
        var total = 0
        for s in activeSubscriptions {
            var days = Set(s.charged.filter { $0 >= lo && $0 < hi })
            for d in s.planned(in: start, end) { days.insert(dayKey(d)) }
            total += days.count * s.amount
        }
        return total
    }

    /// Booked entries in [start, end).
    func entries(between start: Date, _ end: Date) -> [Entry] {
        entries.filter { !$0.pending && $0.date >= start && $0.date < end }
    }

    func monthEntries(_ month: Date) -> [Entry] {
        let p = Cal.parts(month)
        return entries(between: Cal.date(p.year, p.month, 1), Cal.date(p.year, p.month + 1, 1))
    }

    func total(_ kind: EntryKind, _ month: Date) -> Int {
        monthEntries(month).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
    }

    var currency: String { accounts.first?.currency ?? "CNY" }

    func category(_ id: String?) -> LedgerCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func children(of id: String) -> [LedgerCategory] { categories.filter { $0.parentID == id } }

    func isTopLevel(_ c: LedgerCategory) -> Bool { c.parentID == nil || category(c.parentID) == nil }

    func subtreeIDs(_ id: String) -> Set<String> {
        var result: Set<String> = [id]
        var added = true
        while added {
            added = false
            for c in categories where c.parentID != nil && result.contains(c.parentID!) && !result.contains(c.id) {
                result.insert(c.id); added = true
            }
        }
        return result
    }

    func topLevelID(_ id: String) -> String {
        var current = id
        for _ in 0..<10 {
            guard let parent = category(current)?.parentID, category(parent) != nil else { return current }
            current = parent
        }
        return current
    }

    func categorySpending(in list: [Entry]) -> [(LedgerCategory, Int)] {
        var values: [String: Int] = [:]
        for e in list where e.kind == .expense {
            for a in e.allocations { values[a.categoryID, default: 0] += a.amount }
        }
        return categories.filter { $0.kind == .expense && (values[$0.id] ?? 0) != 0 }
            .map { ($0, values[$0.id]!) }
            .enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Like categorySpending, but each subcategory's spending is added to its top-level category.
    func topLevelSpending(in list: [Entry]) -> [(LedgerCategory, Int)] {
        var values: [String: Int] = [:]
        for (c, v) in categorySpending(in: list) { values[topLevelID(c.id), default: 0] += v }
        return categories.filter { (values[$0.id] ?? 0) != 0 }.map { ($0, values[$0.id]!) }
            .enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map(\.element)
    }

    /// The budget in force for a scope in `month`: that month's 本月预算, otherwise the 每月预算.
    func budget(for categoryID: String?, _ month: Date) -> Budget? {
        let m = YearMonth(month)
        var recurring: Budget?
        for b in budgets where b.categoryID == categoryID && b.applies(to: m) {
            if b.month != nil { return b }
            recurring = b
        }
        return recurring
    }

    func budgets(for month: Date) -> [Budget] {
        var scopes: [String?] = []
        for b in budgets where !scopes.contains(where: { $0 == b.categoryID }) { scopes.append(b.categoryID) }
        return scopes.compactMap { budget(for: $0, month) }
    }

    func spent(_ budget: Budget, _ month: Date) -> Int {
        guard let category = budget.categoryID else { return total(.expense, month) }
        let ids = subtreeIDs(category)
        var sum = 0
        for e in monthEntries(month) where e.kind == .expense {
            for a in e.allocations where ids.contains(a.categoryID) { sum += a.amount }
        }
        return sum
    }
}

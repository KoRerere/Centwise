import Foundation
import SQLite3

public struct MigrationSummary: Codable, Sendable {
    public var sourceActiveEntries: Int
    public var importedEntries: Int
    public var accounts: Int
    public var categories: Int
    public var reviewedEntries: Int
    public var incomeCents: Int64
    public var expenseCents: Int64
    public var warnings: [String]
}

public enum MoneyProImporter {
    public static func read(_ url: URL) throws -> (Ledger, MigrationSummary) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = database else {
            if let database { sqlite3_close(database) }
            throw LedgerError.invalid("无法以只读方式打开 Money Pro 数据库。请选择 database.sql，不是 .back 文件。")
        }
        defer { sqlite3_close(db) }
        func rows(_ sql: String) throws -> [[String: String?]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw LedgerError.invalid("旧账本结构不支持：\(String(cString: sqlite3_errmsg(db)))")
            }
            defer { sqlite3_finalize(statement) }
            var result: [[String: String?]] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                var row: [String: String?] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let key = String(cString: sqlite3_column_name(statement, index))
                    let value = sqlite3_column_text(statement, index).map { String(cString: $0) }
                    row.updateValue(value, forKey: key)
                }
                result.append(row)
                guard result.count <= 200_000 else { throw LedgerError.invalid("旧账本表过大，已停止导入。") }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw LedgerError.invalid("读取旧账本失败。") }
            return result
        }
        func value(_ row: [String: String?], _ key: String) -> String { (row[key] ?? nil) ?? "" }
        func integer(_ row: [String: String?], _ key: String) -> Int { Int(value(row, key)) ?? 0 }
        let integrity = try rows("PRAGMA integrity_check")
        guard integrity.count == 1, integrity.first?.values.first.flatMap({ $0 }) == "ok" else {
            throw LedgerError.invalid("旧数据库未通过完整性检查，未导入任何内容。")
        }
        let names = try rows("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { value($0, "name") }
        guard Set(["balance", "category", "transactions", "splitTransaction", "currency"]).isSubset(of: Set(names)) else {
            throw LedgerError.invalid("这不是支持的 Money Pro 账本数据库。")
        }
        var tables: [String: [[String: String?]]] = [:]
        for name in names {
            let safe = name.replacingOccurrences(of: "\"", with: "\"\"")
            tables[name] = try rows("SELECT * FROM \"\(safe)\"")
        }
        var warnings = ["第一版仅迁移人民币账户；余额按旧账户 sum 字段与历史记录推算，尚未与 Money Pro 或银行对账。",
                        "旧预算、循环规则、计划、同步状态和其他源表原字段已归档，但暂不执行；请在 Centwise 重新设置预算。"]
        let accountRows = tables["balance"] ?? []
        var accounts: [Account] = []
        for row in accountRows {
            guard value(row, "currencyKey") == "CNY" else { throw LedgerError.invalid("旧账本包含非人民币账户，第一版无法无损导入，已停止。") }
            accounts.append(Account(id: value(row, "primaryKey"), name: value(row, "name").isEmpty ? "旧账户" : value(row, "name"),
                                    openingBalance: try Money.legacy(value(row, "sum")), archived: integer(row, "isDeleted") != 0 || integer(row, "isHidden") != 0))
        }
        var categories: [LedgerCategory] = []
        for row in tables["category"] ?? [] {
            let type = integer(row, "flowType")
            guard type == 1 || type == 2 else { throw LedgerError.invalid("发现未支持的旧分类类型，已停止导入。") }
            let name = value(row, "name")
            let icon = name.contains("餐") || name.contains("食") ? "fork.knife" : name.contains("交通") ? "tram.fill" : "square.grid.2x2"
            categories.append(LedgerCategory(id: value(row, "primaryKey"), name: name.isEmpty ? "旧分类" : name,
                                       kind: type == 1 ? .income : .expense, symbol: icon,
                                       parentID: value(row, "parentPrimaryKey").isEmpty ? nil : value(row, "parentPrimaryKey")))
        }
        let categoryIDs = Set(categories.map(\.id))
        for index in categories.indices where categories[index].parentID != nil && !categoryIDs.contains(categories[index].parentID!) {
            categories[index].parentID = nil
            warnings.append("有一个旧分类的父分类不存在，已保留为独立分类。")
        }
        let payees = Dictionary(uniqueKeysWithValues: (tables["payee"] ?? []).map { (value($0, "primaryKey"), value($0, "name")) })
        let splits = Dictionary(grouping: tables["splitTransaction"] ?? []) { value($0, "transactionsPrimaryKey") }
        for row in tables["transactions"] ?? [] {
            guard Int(value(row, "isDeleted")) != nil, Int(value(row, "transactionType")) != nil else {
                throw LedgerError.invalid("旧账本缺少有效的交易状态或类型字段，已停止导入。")
            }
        }
        let active = (tables["transactions"] ?? []).filter { integer($0, "isDeleted") == 0 }
        var entries: [Entry] = []
        var recoveredCategories = 0
        var recoveredCategoryIDs = Set<String>()
        for row in active {
            let id = value(row, "primaryKey"), type = integer(row, "transactionType")
            guard integer(row, "isBalanceChange") == 0, value(row, "balanceAdjasmentPK").isEmpty,
                  value(row, "assetsPrimaryKey").isEmpty, value(row, "liabilitiesPrimaryKey").isEmpty,
                  value(row, "secondCashFlowPrimaryKey").isEmpty else {
                throw LedgerError.invalid("发现尚未支持的资产、负债或余额关联，无法确认金额语义，已停止导入。")
            }
            let kind: EntryKind
            switch type { case 0: kind = .expense; case 1: kind = .income
            case 7:
                guard try Money.legacy(value(row, "sum")) == 0 else {
                    throw LedgerError.invalid("发现非零的旧类型 7 记录，无法确认余额语义，已停止导入。")
                }
                kind = .adjustment
            default: throw LedgerError.invalid("旧交易类型 \(type) 尚未实现无损迁移，未修改当前账本。") }
            guard let seconds = Double(value(row, "date")), seconds.isFinite, (0...4_102_444_800).contains(seconds) else {
                throw LedgerError.invalid("旧账本含异常日期，已停止导入。")
            }
            let amount = try Money.legacy(value(row, "sum"))
            var needsReview = type == 7
            let allocations = try (splits[id] ?? []).map { split in
                var categoryID = value(split, "categoryPrimaryKey")
                if categoryID.isEmpty { categoryID = "legacy-unassigned-\(kind.rawValue)" }
                if !categories.contains(where: { $0.id == categoryID }) {
                    categories.append(LedgerCategory(id: categoryID, name: "未识别旧分类", kind: kind, symbol: "questionmark.folder"))
                    recoveredCategories += 1
                    recoveredCategoryIDs.insert(categoryID)
                    needsReview = true
                }
                if recoveredCategoryIDs.contains(categoryID) { needsReview = true }
                return Allocation(categoryID: categoryID, amount: try Money.legacy(value(split, "sum")))
            }
            let entry = Entry(id: id, kind: kind, amount: amount, date: Date(timeIntervalSince1970: seconds),
                              accountID: value(row, "cashFlowPrimaryKey"), allocations: allocations,
                              note: value(row, "description"), payee: payees[value(row, "payeePrimaryKey")] ?? "",
                              pending: integer(row, "isPending") != 0, legacyType: type, needsReview: needsReview)
            entries.append(entry)
        }
        let reviewCount = entries.filter(\.needsReview).count
        let specialCount = entries.filter { $0.legacyType == 7 }.count
        if specialCount > 0 { warnings.append("\(specialCount) 条零金额类型 7 记录保留为待核对的余额调整；不计入收入或支出。") }
        if recoveredCategories > 0 { warnings.append("\(recoveredCategories) 个分摊引用的旧分类已不存在，已建立“未识别旧分类”保留其金额与编号，相关记录标为待核对。") }
        let ledger = Ledger(title: "个人账本", accounts: accounts, categories: categories, entries: entries,
                            legacy: LegacyArchive(tables: tables, warnings: warnings))
        try ledger.validate()
        let summary = MigrationSummary(sourceActiveEntries: active.count, importedEntries: entries.count,
                                       accounts: accounts.count, categories: categories.count, reviewedEntries: reviewCount,
                                       incomeCents: entries.filter { $0.kind == .income && !$0.pending }.reduce(0) { $0 + $1.amount },
                                       expenseCents: entries.filter { $0.kind == .expense && !$0.pending }.reduce(0) { $0 + $1.amount }, warnings: warnings)
        return (ledger, summary)
    }
}

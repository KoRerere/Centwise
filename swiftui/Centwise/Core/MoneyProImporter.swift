import Foundation
import SQLite3

struct MigrationSummary {
    var sourceActiveEntries: Int
    var importedEntries: Int
    var accounts: Int
    var categories: Int
    var reviewedEntries: Int
    var incomeCents: Int
    var expenseCents: Int
    var warnings: [String]
}

/// Read-only migration of a Money Pro `database.sql`. Unknown semantics stop the import instead of
/// being skipped or guessed. All source tables are archived verbatim.
enum MoneyProImporter {
    typealias Row = [String: String?]

    static func read(path: String) throws -> (Ledger, MigrationSummary) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw LedgerError(tr("无法以只读方式打开 Money Pro 数据库。请选择 database.sql，不是 .back 文件。"))
        }
        defer { sqlite3_close(db) }
        return try read(db)
    }

    private static func rows(_ db: OpaquePointer, _ sql: String) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw LedgerError(tr("旧账本结构不支持：") + String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let count = Int(sqlite3_column_count(statement))
        let names = (0..<count).map { String(cString: sqlite3_column_name(statement, Int32($0))) }
        var result: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw LedgerError(tr("旧账本结构不支持：") + String(cString: sqlite3_errmsg(db))) }
            var row: Row = [:]
            for i in 0..<count {
                if sqlite3_column_type(statement, Int32(i)) == SQLITE_NULL {
                    row[names[i]] = .some(nil)
                } else if let text = sqlite3_column_text(statement, Int32(i)) {
                    row[names[i]] = .some(String(cString: text))
                } else {
                    row[names[i]] = .some("")
                }
            }
            result.append(row)
            if result.count > 200_000 { throw LedgerError(tr("旧账本表过大，已停止导入。")) }
        }
        return result
    }

    private static func read(_ db: OpaquePointer) throws -> (Ledger, MigrationSummary) {
        func value(_ row: Row, _ key: String) -> String { (row[key] ?? nil) ?? "" }
        func integer(_ row: Row, _ key: String) -> Int { Int(value(row, key)) ?? 0 }

        let integrity = try rows(db, "PRAGMA integrity_check")
        guard integrity.count == 1, (integrity.first?.values.first ?? nil) == "ok" else {
            throw LedgerError(tr("旧数据库未通过完整性检查，未导入任何内容。"))
        }
        let names = try rows(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").map { value($0, "name") }
        let required: Set<String> = ["balance", "category", "transactions", "splitTransaction", "currency"]
        guard required.isSubset(of: Set(names)) else { throw LedgerError(tr("这不是支持的 Money Pro 账本数据库。")) }

        var tables: [String: [Row]] = [:]
        for name in names {
            tables[name] = try rows(db, "SELECT * FROM \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\"")
        }
        var warnings = [
            "第一版仅迁移人民币账户；余额按旧账户 sum 字段与历史记录推算，尚未与 Money Pro 或银行对账。",
            "旧预算、循环规则、计划、同步状态和其他源表原字段已归档，但暂不执行；请在 Centwise 重新设置预算。",
        ]

        var accounts: [Account] = []
        for row in tables["balance"] ?? [] {
            if value(row, "currencyKey") != "CNY" { throw LedgerError("旧账本包含非人民币账户，第一版无法无损导入，已停止。") }
            accounts.append(Account(id: value(row, "primaryKey"), name: value(row, "name").isEmpty ? "旧账户" : value(row, "name"),
                                    openingBalance: try Money.legacy(value(row, "sum")),
                                    archived: integer(row, "isDeleted") != 0 || integer(row, "isHidden") != 0))
        }

        var categories: [LedgerCategory] = []
        for row in tables["category"] ?? [] {
            let type = integer(row, "flowType")
            if type != 1 && type != 2 { throw LedgerError("发现未支持的旧分类类型，已停止导入。") }
            let parent = value(row, "parentPrimaryKey")
            categories.append(LedgerCategory(id: value(row, "primaryKey"), name: value(row, "name").isEmpty ? "旧分类" : value(row, "name"),
                                             kind: type == 1 ? .income : .expense, symbol: "layout-grid", parentID: parent.isEmpty ? nil : parent))
        }
        let categoryIDs = Set(categories.map(\.id))
        for i in categories.indices where categories[i].parentID != nil && !categoryIDs.contains(categories[i].parentID!) {
            categories[i].parentID = nil
            warnings.append("有一个旧分类的父分类不存在，已保留为独立分类。")
        }

        var payees: [String: String] = [:]
        for row in tables["payee"] ?? [] { payees[value(row, "primaryKey")] = value(row, "name") }
        var splits: [String: [Row]] = [:]
        for row in tables["splitTransaction"] ?? [] { splits[value(row, "transactionsPrimaryKey"), default: []].append(row) }
        let transactionRows = tables["transactions"] ?? []
        for row in transactionRows where Int(value(row, "isDeleted")) == nil || Int(value(row, "transactionType")) == nil {
            throw LedgerError("旧账本缺少有效的交易状态或类型字段，已停止导入。")
        }
        let active = transactionRows.filter { integer($0, "isDeleted") == 0 }
        var entries: [Entry] = []
        var recovered = 0
        var recoveredIDs = Set<String>()
        for row in active {
            let id = value(row, "primaryKey")
            let type = integer(row, "transactionType")
            if integer(row, "isBalanceChange") != 0 || !value(row, "balanceAdjasmentPK").isEmpty || !value(row, "assetsPrimaryKey").isEmpty
                || !value(row, "liabilitiesPrimaryKey").isEmpty || !value(row, "secondCashFlowPrimaryKey").isEmpty {
                throw LedgerError("发现尚未支持的资产、负债或余额关联，无法确认金额语义，已停止导入。")
            }
            let kind: EntryKind
            switch type {
            case 0: kind = .expense
            case 1: kind = .income
            case 7:
                if try Money.legacy(value(row, "sum")) != 0 { throw LedgerError("发现非零的旧类型 7 记录，无法确认余额语义，已停止导入。") }
                kind = .adjustment
            default: throw LedgerError("旧交易类型 \(type) 尚未实现无损迁移，未修改当前账本。")
            }
            guard let seconds = Double(value(row, "date")), seconds.isFinite, seconds >= 0, seconds <= 4_102_444_800 else {
                throw LedgerError("旧账本含异常日期，已停止导入。")
            }
            let amount = try Money.legacy(value(row, "sum"))
            var needsReview = type == 7
            var allocations: [Allocation] = []
            for split in splits[id] ?? [] {
                var categoryID = value(split, "categoryPrimaryKey")
                if categoryID.isEmpty { categoryID = "legacy-unassigned-\(kind.rawValue)" }
                if !categories.contains(where: { $0.id == categoryID }) {
                    categories.append(LedgerCategory(id: categoryID, name: "未识别旧分类", kind: kind, symbol: "folder-search"))
                    recovered += 1; recoveredIDs.insert(categoryID); needsReview = true
                }
                if recoveredIDs.contains(categoryID) { needsReview = true }
                allocations.append(Allocation(categoryID: categoryID, amount: try Money.legacy(value(split, "sum"))))
            }
            entries.append(Entry(id: id, kind: kind, amount: amount, date: Date(timeIntervalSince1970: seconds),
                                 accountID: value(row, "cashFlowPrimaryKey"), allocations: allocations, note: value(row, "description"),
                                 payee: payees[value(row, "payeePrimaryKey")] ?? "", pending: integer(row, "isPending") != 0,
                                 legacyType: type, needsReview: needsReview))
        }
        let reviewCount = entries.filter(\.needsReview).count
        let special = entries.filter { $0.legacyType == 7 }.count
        if special > 0 { warnings.append("\(special) 条零金额类型 7 记录保留为待核对的余额调整；不计入收入或支出。") }
        if recovered > 0 { warnings.append("\(recovered) 个分摊引用的旧分类已不存在，已建立“未识别旧分类”保留其金额与编号，相关记录标为待核对。") }

        var archived: [String: Any] = [:]
        for (name, list) in tables {
            archived[name] = list.map { row -> [String: Any] in
                var out: [String: Any] = [:]
                for (k, v) in row { out[k] = v ?? NSNull() }
                return out
            }
        }
        var ledger = Ledger()
        ledger.title = "个人账本"
        ledger.accounts = accounts
        ledger.categories = categories
        ledger.entries = entries
        ledger.legacy = LegacyArchive(tables: archived, warnings: warnings)
        try ledger.validate()
        func sum(_ kind: EntryKind) -> Int { entries.filter { $0.kind == kind && !$0.pending }.reduce(0) { $0 + $1.amount } }
        let summary = MigrationSummary(sourceActiveEntries: active.count, importedEntries: entries.count, accounts: accounts.count,
                                       categories: categories.count, reviewedEntries: reviewCount, incomeCents: sum(.income),
                                       expenseCents: sum(.expense), warnings: warnings)
        return (ledger, summary)
    }

    /// Money Pro `.back` backups are a sequence of `<path>\n<byte length>\n<bytes>` entries; this
    /// writes the `database.sql` inside to `directory` and returns its path.
    static func extractBack(_ url: URL, into directory: URL) throws -> URL {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        let invalid = LedgerError(tr("无法识别的 Money Pro 备份文件。"))
        func lineEnd(_ from: Int) throws -> Int {
            guard let end = bytes[from...].firstIndex(of: 10) else { throw invalid }
            return end
        }
        var i = 0
        while i < bytes.count {
            let nameEnd = try lineEnd(i)
            let name = String(decoding: bytes[i..<nameEnd], as: UTF8.self)
            let sizeEnd = try lineEnd(nameEnd + 1)
            guard let size = Int(String(decoding: bytes[(nameEnd + 1)..<sizeEnd], as: UTF8.self)), size >= 0,
                  sizeEnd + 1 + size <= bytes.count else { throw invalid }
            if name.hasSuffix("/database.sql") {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let out = directory.appendingPathComponent("database.sql")
                try Data(bytes[(sizeEnd + 1)..<(sizeEnd + 1 + size)]).write(to: out)
                return out
            }
            i = sizeEnd + 1 + size
        }
        throw LedgerError(tr("Money Pro 备份里没有找到账本数据库。"))
    }
}

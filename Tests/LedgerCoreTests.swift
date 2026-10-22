import Foundation
import Testing
@testable import LedgerCore

@Test func amountsAreExact() throws {
    #expect(try Money.parse("0.10") + Money.parse("0.20") == 30)
    #expect(try Money.parse("-26.14") == -2_614)
    #expect(try Money.parse(" 12800.01 ") == 1_280_001)
    #expect(throws: (any Error).self) { try Money.parse("1.001") }
    #expect(throws: (any Error).self) { try Money.parse("NaN") }
    #expect(throws: (any Error).self) { try Money.parse("1,000") }
    #expect(throws: (any Error).self) { try Money.parse("999999999999999999999999") }
    #expect(try Money.legacy("26.140000000000001") == 2_614)
    #expect(throws: (any Error).self) { try Money.legacy("1.2345") }
}

private func sample() -> Ledger {
    var ledger = Ledger.empty()
    ledger.accounts[0].openingBalance = 100_000
    ledger.accounts.append(Account(id: "bank", name: "银行卡", openingBalance: 200_000))
    return ledger
}

@Test func transfersDoNotInflateIncomeOrExpense() throws {
    var ledger = sample()
    ledger.entries = [Entry(kind: .transfer, amount: 12_345, accountID: "cash", destinationID: "bank")]
    try ledger.validate()
    #expect(ledger.balance(of: "cash") == 87_655)
    #expect(ledger.balance(of: "bank") == 212_345)
    #expect(ledger.total(.income, month: .now) == 0)
    #expect(ledger.total(.expense, month: .now) == 0)
}

@Test func pendingDoesNotAffectPostedBalance() throws {
    var ledger = sample()
    ledger.entries = [Entry(kind: .expense, amount: 10_000, accountID: "cash", allocations: [.init(categoryID: "food", amount: 10_000)], pending: true)]
    try ledger.validate()
    #expect(ledger.balance(of: "cash") == 100_000)
    #expect(ledger.total(.expense, month: .now) == 0)
}

@Test func refundsReduceExpenseAndAdjustmentsAreNotIncome() throws {
    var ledger = sample()
    ledger.entries = [Entry(kind: .expense, amount: -1_200, accountID: "cash", allocations: [.init(categoryID: "food", amount: -1_200)]),
                      Entry(kind: .adjustment, amount: -500, accountID: "cash")]
    try ledger.validate()
    #expect(ledger.balance(of: "cash") == 100_700)
    #expect(ledger.total(.expense, month: .now) == -1_200)
    #expect(ledger.total(.income, month: .now) == 0)
}

@Test func splitAllocationsArePreservedAndChecked() throws {
    var ledger = sample()
    ledger.entries = [Entry(kind: .expense, amount: 3_000, accountID: "cash", allocations: [.init(categoryID: "food", amount: 1_200), .init(categoryID: "home", amount: 1_800)])]
    try ledger.validate()
    #expect(ledger.spent(Budget(categoryID: "food", limit: 10_000), month: .now) == 1_200)
    #expect(ledger.spent(Budget(limit: 10_000), month: .now) == 3_000)
    ledger.entries[0].allocations[0].amount = 1_201
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.entries[0].amount = 0
    ledger.entries[0].allocations = [.init(categoryID: "food", amount: Money.maximum), .init(categoryID: "home", amount: -Money.maximum)]
    #expect(throws: (any Error).self) { try ledger.validate() }
}

@Test func invalidDateCannotReachCalendar() throws {
    var ledger = sample()
    ledger.entries = [Entry(kind: .adjustment, amount: 0, date: Date(timeIntervalSince1970: .infinity), accountID: "cash")]
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.entries[0].date = Date(timeIntervalSince1970: .nan)
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.entries[0].date = Date(timeIntervalSince1970: -100)
    #expect(throws: (any Error).self) { try ledger.validate() }
}

@Test func duplicateIDsAndBadReferencesAreRejected() throws {
    var ledger = sample()
    ledger.accounts.append(ledger.accounts[0])
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger = sample()
    ledger.entries = [Entry(kind: .transfer, amount: 100, accountID: "cash", destinationID: "cash")]
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.entries[0].destinationID = "missing"
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger = sample()
    ledger.entries = [Entry(kind: .expense, amount: 100, accountID: "cash", allocations: [.init(categoryID: "salary", amount: 100)])]
    #expect(throws: (any Error).self) { try ledger.validate() }
}

@Test func duplicateBudgetsAndForeignCurrencyAreRejected() throws {
    var ledger = sample()
    ledger.budgets = [Budget(limit: 100), Budget(limit: 200)]
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.budgets = [Budget(categoryID: "salary", limit: 100)]
    #expect(throws: (any Error).self) { try ledger.validate() }
    ledger.budgets = []
    ledger.accounts[0].currency = "USD"
    #expect(throws: (any Error).self) { try ledger.validate() }
}

@Test func monthBoundariesAreHalfOpen() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
    let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
    let end = calendar.date(byAdding: .month, value: 1, to: start)!
    var ledger = sample()
    ledger.entries = [Entry(id: "first", kind: .adjustment, amount: 0, date: start, accountID: "cash"),
                      Entry(id: "last", kind: .adjustment, amount: 0, date: end.addingTimeInterval(-1), accountID: "cash"),
                      Entry(id: "next", kind: .adjustment, amount: 0, date: end, accountID: "cash")]
    try ledger.validate()
    #expect(Set(ledger.monthEntries(start, calendar: calendar).map(\.id)) == Set(["first", "last"]))
}

@Test func backupRoundTripPreservesAllFields() throws {
    var ledger = Ledger.demo()
    ledger.legacy = LegacyArchive(tables: ["extra": [["nullable": nil, "amount": "0.10"]]], warnings: ["保留原始字段"])
    let encoded = try LedgerCodec.encode(ledger)
    let decoded = try LedgerCodec.decode(encoded)
    #expect(decoded == ledger)
    ledger.schemaVersion = 2
    #expect(throws: (any Error).self) { try LedgerCodec.encode(ledger) }
}

@Test func repositoryCreatesSnapshotAndFailedSaveLeavesOriginal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("centwise-test-\(UUID().uuidString)")
    let repository = LedgerRepository(directory: directory)
    #expect(try repository.load() == nil)
    var ledger = sample()
    try repository.save(ledger)
    ledger.title = "修改后"
    try repository.save(ledger)
    #expect(try repository.load()?.title == "修改后")
    let backups = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
    #expect(backups.count == 2)
    #expect(try LedgerCodec.decode(Data(contentsOf: backups[0])).title == "我的账本")
    ledger.entries = [Entry(kind: .transfer, amount: -1, accountID: "cash", destinationID: "bank")]
    #expect(throws: (any Error).self) { try repository.save(ledger) }
    #expect(try repository.load()?.title == "修改后")
    var replacement = sample(); replacement.title = "导入替换"
    try repository.save(replacement, preserveImportSnapshot: true)
    let afterImport = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
    #expect(afterImport.count == 3)
    let importBackup = try #require(afterImport.first { $0.lastPathComponent.hasPrefix("before-import-") })
    #expect(try LedgerCodec.decode(Data(contentsOf: importBackup)).title == "修改后")
    // Only remove this test's explicitly created temporary directory.
    try FileManager.default.removeItem(at: directory)
}

@Test func corruptedBackupIsNotSilentlyReplaced() throws {
    #expect(throws: (any Error).self) { try LedgerCodec.decode(Data("not a ledger".utf8)) }
}

@Test func newExportCannotOverwriteExistingFile() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("centwise-export-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("backup.qingledger")
    let original = Data("original".utf8)
    try LedgerFiles.createNew(original, at: url)
    #expect(throws: (any Error).self) { try LedgerFiles.createNew(Data("replacement".utf8), at: url) }
    #expect(try Data(contentsOf: url) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["backup.qingledger"])
    try FileManager.default.removeItem(at: directory)
}

/// Opt-in integration check uses a local path; real ledger data is never a source/test fixture.
@Test func actualMoneyProMigrationWhenProvided() throws {
    guard let path = ProcessInfo.processInfo.environment["CENTWISE_LEGACY_DB"] ?? ProcessInfo.processInfo.environment["QINGLEDGER_LEGACY_DB"] else { return }
    let url = URL(fileURLWithPath: path)
    let before = try Data(contentsOf: url)
    let (ledger, summary) = try MoneyProImporter.read(url)
    #expect(summary.sourceActiveEntries == 4_674)
    #expect(summary.importedEntries == 4_674)
    #expect(summary.reviewedEntries == 2)
    #expect(ledger.entries.filter { $0.kind == .expense }.count == 4_618)
    #expect(ledger.entries.filter { $0.kind == .income }.count == 55)
    #expect(ledger.entries.filter { $0.kind == .income }.flatMap(\.allocations).count == 56)
    #expect(try Data(contentsOf: url) == before)
    #expect(try LedgerCodec.decode(LedgerCodec.encode(ledger)) == ledger)
    #expect(ledger.legacy?.tables["periodicity"]?.count == 4_675)
    let sourceRows = try #require(ledger.legacy?.tables["transactions"])
    let activeRows = sourceRows.filter { ($0["isDeleted"] ?? nil) == "0" }
    let sourceIncome = try activeRows.filter { ($0["transactionType"] ?? nil) == "1" }
        .reduce(Int64(0)) { $0 + (try Money.legacy(($1["sum"] ?? nil) ?? "")) }
    let sourceExpense = try activeRows.filter { ($0["transactionType"] ?? nil) == "0" }
        .reduce(Int64(0)) { $0 + (try Money.legacy(($1["sum"] ?? nil) ?? "")) }
    #expect(summary.incomeCents == sourceIncome)
    #expect(summary.expenseCents == sourceExpense)
    #expect(Set(activeRows.compactMap { $0["primaryKey"] ?? nil }) == Set(ledger.entries.map(\.id)))
    for entry in ledger.entries {
        let source = try #require(activeRows.first { ($0["primaryKey"] ?? nil) == entry.id })
        #expect(entry.amount == (try Money.legacy((source["sum"] ?? nil) ?? "")))
        #expect(entry.note == ((source["description"] ?? nil) ?? ""))
        #expect(entry.date.timeIntervalSince1970 == Double((source["date"] ?? nil) ?? ""))
    }
}

import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import LedgerCore
#endif

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var ledger: Ledger
    @Published var error: String?
    @Published var loadingFailed = false
    @Published var pendingImport: Ledger?
    @Published var importDescription = ""
    /// Anchor date of the selected period (named `month` for older call sites).
    @Published var month = Date.now
    /// Default timeline is today; the bottom capsule switches between today and this month.
    @Published var period: Period = .day
    let repository: LedgerRepository
    let isDemo: Bool

    init() {
        isDemo = ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["CENTWISE_DEMO"] == "1"
            || ProcessInfo.processInfo.environment["QINGLEDGER_DEMO"] == "1"
        // The data folder keeps its original name so the existing ledger on the phone is still found.
        #if os(iOS)
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("QingLedger", isDirectory: true)
        #else
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QingLedger", isDirectory: true)
        #endif
        repository = LedgerRepository(directory: directory)
        ledger = isDemo ? .demo() : .empty()
        if !isDemo {
            do { ledger = try repository.load() ?? .empty() }
            catch { self.error = "账本读取失败：\(error.localizedDescription)\n原文件已保留，暂停所有写入。请导入已核对的备份。"; loadingFailed = true }
        }
    }

    @discardableResult
    func commit(_ change: (inout Ledger) throws -> Void) -> Bool {
        guard !loadingFailed else { error = "读取失败期间禁止修改账本，请先恢复备份。"; return false }
        do {
            var next = ledger
            try change(&next)
            try next.validate()
            if !isDemo { try repository.save(next) }
            ledger = next
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func save(_ entry: Entry) -> Bool {
        commit { ledger in
            if let index = ledger.entries.firstIndex(where: { $0.id == entry.id }) { ledger.entries[index] = entry }
            else { ledger.entries.append(entry) }
        }
    }
    func delete(_ entry: Entry) { _ = commit { $0.entries.removeAll { $0.id == entry.id } } }

    func prepareImport(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let next: Ledger
            if url.pathExtension.lowercased() == "sql" || url.pathExtension.lowercased() == "sqlite" {
                let result = try MoneyProImporter.read(url)
                next = result.0
                importDescription = "Money Pro：\(result.1.importedEntries) 条记录、\(result.1.accounts) 个账户、\(result.1.categories) 个分类。\n" + result.1.warnings.joined(separator: "\n")
            } else {
                next = try LedgerCodec.decode(Data(contentsOf: url))
                importDescription = "\(next.title)：\(next.entries.count) 条记录、\(next.accounts.count) 个账户。"
                let review = next.entries.filter(\.needsReview).count
                if review > 0 { importDescription += "\n\(review) 条记录需要核对。" }
                if let warnings = next.legacy?.warnings { importDescription += "\n" + warnings.joined(separator: "\n") }
            }
            pendingImport = next
        } catch { self.error = "导入失败，当前账本未改动：\(error.localizedDescription)" }
    }

    func confirmImport() {
        guard let next = pendingImport else { return }
        do {
            try next.validate()
            if !isDemo { try repository.save(next, preserveImportSnapshot: true) }
            ledger = next; loadingFailed = false; pendingImport = nil
            month = next.entries.map(\.date).max() ?? .now
            period = .month
        } catch { self.error = "恢复失败，当前账本未改动：\(error.localizedDescription)" }
    }

    func categoryName(_ entry: Entry) -> String {
        if entry.kind == .transfer { return "账户转账" }
        if entry.kind == .adjustment { return "余额调整" }
        let ids = Set(entry.allocations.map(\.categoryID))
        return ledger.categories.filter { ids.contains($0.id) }.map(\.name).joined(separator: " / ")
    }
    func accountName(_ id: String) -> String { ledger.accounts.first { $0.id == id }?.name ?? "未知账户" }

    // MARK: Selected period (today / this month / last 12 months)

    enum Period: String { case day, month, year }

    var interval: DateInterval { periodInterval(containing: month) }
    func periodInterval(containing date: Date) -> DateInterval {
        let calendar = Calendar.current
        switch period {
        case .day:
            return calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 86_400 * 30)
        case .year:
            // Rolling 12 months ending with the anchor month (this month included).
            let monthInterval = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 86_400 * 30)
            let start = calendar.date(byAdding: .month, value: -11, to: monthInterval.start) ?? monthInterval.start
            return DateInterval(start: start, end: monthInterval.end)
        }
    }
    /// The same period one step earlier (yesterday / last month / the 12 months before), for comparisons.
    var previousInterval: DateInterval {
        periodInterval(containing: Calendar.current.date(byAdding: stepComponent.0, value: -stepComponent.1, to: month) ?? month)
    }
    private var stepComponent: (Calendar.Component, Int) {
        switch period { case .day: (.day, 1); case .month: (.month, 1); case .year: (.month, 12) }
    }
    func entries(in interval: DateInterval) -> [Entry] {
        ledger.entries.filter { !$0.pending && $0.date >= interval.start && $0.date < interval.end }
    }
    /// Booked (non-pending) entries in the selected period, newest first.
    var periodEntries: [Entry] { entries(in: interval).sorted { $0.date > $1.date } }
    func periodTotal(_ kind: EntryKind) -> Int64 {
        entries(in: interval).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
    }
    var periodCategorySpending: [(category: LedgerCategory, amount: Int64)] {
        var values: [String: Int64] = [:]
        for entry in entries(in: interval) where entry.kind == .expense {
            for allocation in entry.allocations { values[allocation.categoryID, default: 0] += allocation.amount }
        }
        return ledger.categories.filter { $0.kind == .expense }.map { ($0, values[$0.id] ?? 0) }
            .filter { $0.1 != 0 }.sorted { $0.1 > $1.1 }
    }
    var isCurrentPeriod: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: period == .day ? .day : .month)
    }

    /// The 12 months of the rolling-year window, oldest first, with booked income and expense.
    struct MonthTotal: Identifiable { let month: Date; let income: Int64; let expense: Int64; var id: Date { month } }
    var yearMonths: [MonthTotal] {
        let calendar = Calendar.current
        let start = periodInterval(containing: month).start
        return (0..<12).compactMap { offset in
            guard let value = calendar.date(byAdding: .month, value: offset, to: start) else { return nil }
            return MonthTotal(month: value, income: ledger.total(.income, month: value), expense: ledger.total(.expense, month: value))
        }
    }
    /// Months counted for the monthly average: the window's months from the first recorded entry onwards.
    /// The current, unfinished month counts as a whole month.
    var averageMonthCount: Int {
        guard let first = ledger.entries.map(\.date).min() else { return 12 }
        let calendar = Calendar.current
        let firstMonth = calendar.dateInterval(of: .month, for: first)?.start ?? first
        return max(1, yearMonths.filter { $0.month >= firstMonth }.count)
    }
    func monthlyAverage(_ kind: EntryKind) -> Int64 {
        let total = yearMonths.reduce(Int64(0)) { $0 + (kind == .income ? $1.income : $1.expense) }
        return total / Int64(averageMonthCount)
    }

    /// Short label for captions: 今日 / 本月 / 近一年.
    var periodWord: String {
        switch period { case .day: "今日"; case .month: "本月"; case .year: "近一年" }
    }
    /// Segment title: "今天" / "本月" / "近一年", or the specific day / month when browsing away from now.
    var periodName: String {
        let calendar = Calendar.current
        let thisYear = calendar.isDate(month, equalTo: .now, toGranularity: .year)
        switch period {
        case .day:
            if calendar.isDateInToday(month) { return "今天" }
            if calendar.isDateInYesterday(month) { return "昨天" }
            return thisYear ? month.formatted(.dateTime.month(.defaultDigits).day())
                            : month.formatted(.dateTime.year().month(.defaultDigits).day())
        case .month:
            if calendar.isDate(month, equalTo: .now, toGranularity: .month) { return "本月" }
            return thisYear ? month.formatted(.dateTime.month(.wide)) : month.formatted(.dateTime.year().month(.wide))
        case .year:
            if calendar.isDate(month, equalTo: .now, toGranularity: .month) { return "近一年" }
            return "至" + month.formatted(.dateTime.year().month(.defaultDigits))
        }
    }
    /// Full range text, e.g. "2025年11月 – 2026年10月", shown under the year view.
    var yearRangeText: String {
        let window = periodInterval(containing: month)
        let last = Calendar.current.date(byAdding: .day, value: -1, to: window.end) ?? window.end
        return window.start.formatted(.dateTime.year().month(.defaultDigits)) + " – " + last.formatted(.dateTime.year().month(.defaultDigits))
    }
    func stepPeriod(_ value: Int) {
        month = Calendar.current.date(byAdding: stepComponent.0, value: value * stepComponent.1, to: month) ?? .now
    }
    /// Tapping a segment: switch mode, or jump back to now if it is already selected.
    func select(_ next: Period) {
        if period == next { month = .now } else { period = next }
    }
}

struct BackupDocument: FileDocument {
    static let contentType = UTType(exportedAs: "com.koray.qingledger.backup", conformingTo: .json)
    static var readableContentTypes: [UTType] { [contentType, .json, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LedgerError.invalid("备份不是普通文件。") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

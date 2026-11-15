import Foundation
import Observation
import SwiftUI

enum Period: String { case day, month, year }

enum ThemeMode: String, CaseIterable { case system, light, dark }

struct MonthTotal { let month: Date; let income: Int; let expense: Int }

/// App state: the ledger, the selected period, persistence and import.
@Observable
final class LedgerStore {
    let repository: LedgerRepository?
    let isDemo: Bool
    private(set) var ledger: Ledger

    var error: String?
    var loadingFailed = false
    var pendingImport: Ledger?
    var importDescription = ""

    /// Anchor date of the selected period.
    var month = Date()
    /// Default timeline is today; the bottom capsule switches between today, this month and the last 12 months.
    var period: Period = .day

    var themeMode: ThemeMode = .system
    var languagePref: LanguagePref = .system
    /// Bumped when the language changes so every view re-renders its translated text.
    var languageVersion = 0

    /// Entries deleted in the last few seconds that 撤销 would bring back.
    var recentlyDeleted: [Entry] = []
    private var undoTask: Task<Void, Never>?
    private var today = Cal.dateOnly(Date())

    private init(repository: LedgerRepository?, isDemo: Bool, ledger: Ledger) {
        self.repository = repository
        self.isDemo = isDemo
        self.ledger = ledger
        syncCurrency()
    }

    static func open() -> LedgerStore {
        let defaults = UserDefaults.standard
        let theme = ThemeMode(rawValue: defaults.string(forKey: "themeMode") ?? "") ?? .system
        let language = LanguagePref(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        L10n.current = L10n.resolve(language)
        let store = openLedger()
        store.themeMode = theme
        store.languagePref = language
        return store
    }

    private static func openLedger() -> LedgerStore {
        let env = ProcessInfo.processInfo.environment
        if env["CENTWISE_DEMO"] == "1" || UserDefaults.standard.bool(forKey: "CWDemo") {
            return LedgerStore(repository: nil, isDemo: true, ledger: .demo())
        }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let repository = LedgerRepository(directory: base.appendingPathComponent("Centwise", isDirectory: true))
        do {
            return LedgerStore(repository: repository, isDemo: false, ledger: try repository.load() ?? .empty())
        } catch {
            let store = LedgerStore(repository: repository, isDemo: false, ledger: .empty())
            store.error = tr("账本读取失败：{error}\n原文件已保留，暂停所有写入。请导入已核对的备份。", ["error": "\(error)"])
            store.loadingFailed = true
            return store
        }
    }

    private func syncCurrency() { Money.symbol = currencyFor(ledger.currency).symbol }

    var colorScheme: ColorScheme? {
        switch themeMode { case .system: nil; case .light: .light; case .dark: .dark }
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "themeMode")
    }

    func setLanguage(_ pref: LanguagePref) {
        languagePref = pref
        L10n.current = L10n.resolve(pref)
        UserDefaults.standard.set(pref.rawValue, forKey: "language")
        languageVersion += 1
    }

    @discardableResult
    func setCurrency(_ code: String) -> Bool {
        commit { ledger in for i in ledger.accounts.indices { ledger.accounts[i].currency = code } }
    }

    // MARK: Writing

    /// Applies `change` to a copy, validates and saves it; the visible ledger only changes on success.
    @discardableResult
    func commit(_ change: (inout Ledger) throws -> Void) -> Bool {
        if loadingFailed {
            error = tr("读取失败期间禁止修改账本，请先恢复备份。")
            return false
        }
        do {
            var next = ledger
            try change(&next)
            try next.validate()
            if !isDemo { try repository?.save(next) }
            ledger = next
            syncCurrency()
            return true
        } catch {
            self.error = "\(error)"
            return false
        }
    }

    @discardableResult
    func save(_ entry: Entry) -> Bool {
        commit { ledger in
            if let i = ledger.entries.firstIndex(where: { $0.id == entry.id }) { ledger.entries[i] = entry } else { ledger.entries.append(entry) }
        }
    }

    // MARK: Hidden default account

    static func defaultAccount(in ledger: inout Ledger) -> String {
        if let a = ledger.accounts.first(where: { !$0.archived }) { return a.id }
        let account = Account(name: tr("日常账户"), currency: ledger.currency)
        ledger.accounts.append(account)
        return account.id
    }

    func defaultAccountID() -> String? {
        if let a = ledger.accounts.first(where: { !$0.archived }) { return a.id }
        var id: String?
        return commit { ledger in id = LedgerStore.defaultAccount(in: &ledger) } ? id : nil
    }

    // MARK: Subscriptions

    private static func subscriptionIndex(_ ledger: Ledger, _ id: String) throws -> Int {
        guard let i = ledger.subscriptions.firstIndex(where: { $0.id == id }) else { throw LedgerError(tr("找不到这个订阅。")) }
        return i
    }

    @discardableResult
    func saveSubscription(_ s: Subscription) -> Bool {
        commit { ledger in
            if let i = ledger.subscriptions.firstIndex(where: { $0.id == s.id }) { ledger.subscriptions[i] = s } else { ledger.subscriptions.append(s) }
        }
    }

    @discardableResult
    func cancelSubscription(_ id: String) -> Bool {
        commit { ledger in
            let i = try LedgerStore.subscriptionIndex(ledger, id)
            ledger.subscriptions[i].cancelled = true
            ledger.subscriptions[i].cancelledAt = Date()
        }
    }

    @discardableResult
    func resumeSubscription(_ id: String) -> Bool {
        commit { ledger in
            let i = try LedgerStore.subscriptionIndex(ledger, id)
            ledger.subscriptions[i].cancelled = false
            ledger.subscriptions[i].cancelledAt = nil
            let today = Cal.dateOnly(Date())
            var guardCount = 0
            while guardCount < 400 && ledger.subscriptions[i].nextDate < today {
                ledger.subscriptions[i].nextDate = ledger.subscriptions[i].after(ledger.subscriptions[i].nextDate)
                guardCount += 1
            }
        }
    }

    @discardableResult
    func confirmSubscriptionCharge(_ id: String) -> Bool {
        commit { ledger in
            let i = try LedgerStore.subscriptionIndex(ledger, id)
            let s = ledger.subscriptions[i]
            let now = Date()
            if !s.isDue(now) { throw LedgerError(tr("这一期还没到扣费日期。")) }
            let key = dayKey(s.nextDate)
            if !s.charged.contains(key) {
                let day = s.nextDate
                let p = Cal.parts(day)
                let category = LedgerStore.subscriptionCategory(in: &ledger, s)
                let account = LedgerStore.defaultAccount(in: &ledger)
                let note = s.note.trimmingCharacters(in: .whitespaces)
                ledger.entries.append(Entry(kind: .expense, amount: s.amount, date: Cal.sameDay(now, day) ? now : Cal.date(p.year, p.month, p.day, 12),
                                            accountID: account, allocations: [Allocation(categoryID: category, amount: s.amount)],
                                            note: note.isEmpty ? s.name : "\(s.name) · \(note)", payee: s.name))
                ledger.subscriptions[i].charged.append(key)
            }
            ledger.subscriptions[i].nextDate = s.after(s.nextDate)
        }
    }

    @discardableResult
    func skipSubscriptionCharge(_ id: String) -> Bool {
        commit { ledger in
            let i = try LedgerStore.subscriptionIndex(ledger, id)
            if !ledger.subscriptions[i].isDue(Date()) { throw LedgerError(tr("这一期还没到扣费日期。")) }
            ledger.subscriptions[i].nextDate = ledger.subscriptions[i].after(ledger.subscriptions[i].nextDate)
        }
    }

    private static func subscriptionCategory(in ledger: inout Ledger, _ s: Subscription) -> String {
        if let own = ledger.category(s.categoryID), own.kind == .expense { return own.id }
        if let other = otherCategory(in: ledger, .expense) { return other.id }
        let created = LedgerCategory(name: tr("其他"), kind: .expense, symbol: "ellipsis")
        ledger.categories.append(created)
        return created.id
    }

    /// The ledger's own top-level "其他" category of that kind, or nil when there is none yet. Subcategories
    /// named 其他 / 其它 (出行 › 其它, say) never count: an uncategorised bill belongs to the standalone one.
    func otherCategory(_ kind: EntryKind) -> LedgerCategory? { LedgerStore.otherCategory(in: ledger, kind) }

    static func otherCategory(in ledger: Ledger, _ kind: EntryKind) -> LedgerCategory? {
        let names = kind == .income ? ["其他收入", "其它收入", "其他", "其它", tr("其他收入"), tr("其他")] : ["其他", "其它", "其他支出", "其它支出", tr("其他")]
        for name in names {
            if let c = ledger.categories.first(where: { $0.kind == kind && ledger.isTopLevel($0) && $0.name.trimmingCharacters(in: .whitespaces) == name }) { return c }
        }
        return nil
    }

    // MARK: Import

    func prepareImport(_ url: URL) {
        do {
            let lower = url.path.lowercased()
            let next: Ledger
            if lower.hasSuffix(".sql") || lower.hasSuffix(".sqlite") || lower.hasSuffix(".back") {
                var source = url
                var unpacked: URL?
                if lower.hasSuffix(".back") {
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("centwise-back-\(newID())")
                    source = try MoneyProImporter.extractBack(url, into: dir)
                    unpacked = dir
                }
                let (ledger, summary) = try MoneyProImporter.read(path: source.path)
                if let unpacked { try? FileManager.default.removeItem(at: unpacked) }
                next = ledger
                importDescription = tr("Money Pro：{entries} 条记录、{accounts} 个账户、{categories} 个分类。",
                                       ["entries": summary.importedEntries, "accounts": summary.accounts, "categories": summary.categories])
                    + "\n" + summary.warnings.joined(separator: "\n")
            } else {
                next = try LedgerCodec.decode(Data(contentsOf: url))
                var text = tr("{title}：{entries} 条记录、{accounts} 个账户。", ["title": next.title, "entries": next.entries.count, "accounts": next.accounts.count])
                let review = next.entries.filter(\.needsReview).count
                if review > 0 { text += "\n" + tr("{n} 条记录需要核对。", ["n": review]) }
                if let warnings = next.legacy?.warnings, !warnings.isEmpty { text += "\n" + warnings.joined(separator: "\n") }
                importDescription = text
            }
            pendingImport = next
        } catch {
            self.error = tr("导入失败，当前账本未改动：{error}", ["error": "\(error)"])
        }
    }

    /// Import inbox: a backup in `<data>/Import/` or (Finder file sharing) the top of Documents opens the
    /// import preview at launch, then moves to `Import/Done/`.
    func scanImportFolder() {
        guard let repo = repository, pendingImport == nil else { return }
        let fm = FileManager.default
        let inbox = repo.directory.appendingPathComponent("Import", isDirectory: true)
        let types = [".sql", ".sqlite", ".back", ".centwise", ".qingledger"]
        func candidates(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { url in types.contains { url.lastPathComponent.lowercased().hasSuffix($0) } }
                .sorted { $0.path < $1.path }
        }
        let files = candidates(inbox) + candidates(repo.directory.deletingLastPathComponent())
        guard let file = files.first else { return }
        prepareImport(file)
        let done = inbox.appendingPathComponent("Done", isDirectory: true)
        try? fm.createDirectory(at: done, withIntermediateDirectories: true)
        try? fm.moveItem(at: file, to: done.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))-\(file.lastPathComponent)"))
    }

    func cancelImport() { pendingImport = nil }

    func confirmImport() {
        guard let next = pendingImport else { return }
        do {
            try next.validate()
            if !isDemo { try repository?.save(next, preserveImportSnapshot: true) }
            ledger = next
            syncCurrency()
            loadingFailed = false
            pendingImport = nil
            month = next.entries.map(\.date).max() ?? Date()
            period = .month
        } catch {
            self.error = tr("恢复失败，当前账本未改动：{error}", ["error": "\(error)"])
        }
    }

    // MARK: Delete with undo

    static let undoWindow: Duration = .seconds(5)

    @discardableResult
    func deleteEntry(_ entry: Entry) -> Bool {
        let ok = commit { ledger in ledger.entries.removeAll { $0.id == entry.id } }
        if ok {
            recentlyDeleted.append(entry)
            undoTask?.cancel()
            undoTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: LedgerStore.undoWindow)
                if !Task.isCancelled { self?.dismissUndo() }
            }
        }
        return ok
    }

    @discardableResult
    func undoDelete() -> Bool {
        guard !recentlyDeleted.isEmpty else { return false }
        let restore = recentlyDeleted
        undoTask?.cancel()
        recentlyDeleted.removeAll()
        return commit { ledger in
            for e in restore where !ledger.entries.contains(where: { $0.id == e.id }) { ledger.entries.append(e) }
        }
    }

    func dismissUndo() {
        undoTask?.cancel()
        if !recentlyDeleted.isEmpty { recentlyDeleted.removeAll() }
    }

    // MARK: Day change

    /// When the date changed: if the user was following the current period, move with it.
    func refreshDay() {
        let now = Cal.dateOnly(Date())
        if now == today { return }
        let following = isCurrentPeriod(on: today)
        today = now
        if following { month = Date() }
    }

    private func isCurrentPeriod(on day: Date) -> Bool {
        switch period {
        case .day: Cal.sameDay(month, day)
        case .month: Cal.sameMonth(month, day)
        case .year: Cal.year(month) == Cal.year(day)
        }
    }

    // MARK: Lookups

    func categoryName(_ entry: Entry) -> String {
        if entry.kind == .transfer { return tr("账户转账") }
        if entry.kind == .adjustment { return tr("余额调整") }
        let ids = Set(entry.allocations.map(\.categoryID))
        return ledger.categories.filter { ids.contains($0.id) }.map(\.name).joined(separator: " / ")
    }

    func accountName(_ id: String) -> String { ledger.accounts.first { $0.id == id }?.name ?? tr("未知账户") }

    func category(_ id: String?) -> LedgerCategory? { ledger.category(id) }

    // MARK: Selected period

    func interval(containing date: Date) -> (Date, Date) {
        let p = Cal.parts(date)
        switch period {
        case .day: return (Cal.date(p.year, p.month, p.day), Cal.date(p.year, p.month, p.day + 1))
        case .month: return (Cal.date(p.year, p.month, 1), Cal.date(p.year, p.month + 1, 1))
        // 今年: the calendar year, January to December.
        case .year: return (Cal.date(p.year, 1, 1), Cal.date(p.year + 1, 1, 1))
        }
    }

    var interval: (Date, Date) { interval(containing: month) }

    private func shift(_ date: Date, _ steps: Int) -> Date {
        let p = Cal.parts(date)
        switch period {
        case .day: return Cal.date(p.year, p.month, p.day + steps, p.hour, p.minute)
        case .month: return Cal.date(p.year, p.month + steps, 1)
        case .year: return Cal.date(p.year, p.month + steps * 12, 1)
        }
    }

    var previousInterval: (Date, Date) { interval(containing: shift(month, -1)) }

    func entries(in range: (Date, Date)) -> [Entry] { ledger.entries(between: range.0, range.1) }

    /// Booked entries in the selected period, newest first.
    var periodEntries: [Entry] { entries(in: interval).sorted { $0.date > $1.date } }

    var periodCategorySpending: [(LedgerCategory, Int)] { ledger.categorySpending(in: entries(in: interval)) }

    var isCurrentPeriod: Bool { isCurrentPeriod(on: Date()) }

    var yearMonths: [MonthTotal] {
        let start = interval(containing: month).0
        let p = Cal.parts(start)
        return (0..<12).map { i in
            let m = Cal.date(p.year, p.month + i, 1)
            return MonthTotal(month: m, income: ledger.total(.income, m), expense: ledger.total(.expense, m))
        }
    }

    /// Months counted for the monthly average: the window's months from the first recorded entry onwards.
    var averageMonthCount: Int {
        // Months of the year from the first recorded entry up to this month (later months haven't happened).
        let firstMonth = ledger.entries.map(\.date).min().map(Cal.monthStart) ?? .distantPast
        let thisMonth = Cal.monthStart(Date())
        let count = yearMonths.filter { $0.month >= firstMonth && $0.month <= thisMonth }.count
        return max(count, 1)
    }

    func monthlyAverage(_ kind: EntryKind) -> Int {
        let months = yearMonths
        let total = months.reduce(0) { $0 + (kind == .income ? $1.income : $1.expense) }
        return total / averageMonthCount
    }

    /// 今日 / 本月 / 今年.
    var periodWord: String {
        switch period {
        case .day: tr("今日", ctx: "period")
        case .month: tr("本月", ctx: "period")
        case .year: tr("今年", ctx: "period")
        }
    }

    /// "今天" / "本月" / "今年", or the specific day / month when browsing away from now.
    var periodName: String {
        let now = Date()
        let thisYear = Cal.year(month) == Cal.year(now)
        switch period {
        case .day:
            let difference = Cal.daysBetween(month, now)
            if difference == 0 { return tr("今天") }
            if difference == 1 { return tr("昨天") }
            return thisYear ? fmtMonthDay(month) : fmtYMD(month)
        case .month:
            if Cal.sameMonth(month, now) { return tr("本月") }
            return thisYear ? fmtMonth(month) : fmtYearMonth(month)
        case .year:
            if thisYear { return tr("今年") }
            return tr("{year}年", ["year": Cal.year(month)])
        }
    }

    var yearRangeText: String {
        let (start, end) = interval(containing: month)
        let p = Cal.parts(end)
        return "\(fmtYearMonth(start)) – \(fmtYearMonth(Cal.date(p.year, p.month - 1, 1)))"
    }

    func stepPeriod(_ value: Int) { month = shift(month, value) }

    /// Tapping a segment: switch mode, or jump back to now if it is already selected.
    func select(_ next: Period) {
        if period == next { month = Date() } else { period = next }
    }
}

import Foundation

/// JSON backup format, compatible with `.centwise` (Flutter) and `.qingledger` (old SwiftUI) files:
/// same keys, sorted; dates as seconds since 2001-01-01; `schemaVersion` 1.
enum LedgerCodec {
    static let maxBytes = 100_000_000

    static func encode(_ ledger: Ledger) throws -> Data {
        try ledger.validate()
        let data = try JSONSerialization.data(withJSONObject: ledger.json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if data.count > maxBytes { throw LedgerError(tr("账本超过第一版 100 MB 文件限制，已停止保存或导出。")) }
        return data
    }

    static func decode(_ data: Data) throws -> Ledger {
        if data.count > maxBytes { throw LedgerError(tr("备份文件超过 100 MB，已停止导入。")) }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) } catch {
            throw LedgerError(tr("这不是有效的 Centwise 备份文件。"))
        }
        guard let json = object as? JSON else { throw LedgerError(tr("这不是有效的 Centwise 备份文件。")) }
        let ledger: Ledger
        do { ledger = try Ledger(json: json) } catch let e as LedgerError { throw e } catch {
            throw LedgerError(tr("备份文件结构不完整，无法读取。"))
        }
        try ledger.validate()
        return ledger
    }
}

enum LedgerFiles {
    /// Write to a sibling temp file and rename over the target, so a crash never leaves half a file.
    static func writeAtomic(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// A failed load is surfaced to the UI and never silently replaced with an empty ledger.
struct LedgerRepository {
    let directory: URL
    var file: URL { directory.appendingPathComponent("ledger.centwise") }
    var backups: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    func load() throws -> Ledger? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try LedgerCodec.decode(Data(contentsOf: file))
    }

    func save(_ ledger: Ledger, preserveImportSnapshot: Bool = false) throws {
        let data = try LedgerCodec.encode(ledger)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path) {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let daily = backups.appendingPathComponent("daily-\(dayKey(Date())).centwise")
            if !fm.fileExists(atPath: daily.path) { try fm.copyItem(at: file, to: daily) }
            if preserveImportSnapshot {
                try fm.copyItem(at: file, to: backups.appendingPathComponent("before-import-\(newID()).centwise"))
            }
            try LedgerFiles.writeAtomic(Data(contentsOf: file), to: backups.appendingPathComponent("last-good.centwise"))
        }
        try LedgerFiles.writeAtomic(data, to: file)
    }
}

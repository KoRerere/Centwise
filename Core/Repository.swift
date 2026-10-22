import Foundation

public enum LedgerCodec {
    public static func encode(_ ledger: Ledger) throws -> Data {
        try ledger.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Native Codable Date seconds since 2001 preserve the exact Foundation representation.
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(ledger)
        guard data.count <= 100_000_000 else { throw LedgerError.invalid("账本超过第一版 100 MB 文件限制，已停止保存或导出。") }
        return data
    }
    public static func decode(_ data: Data) throws -> Ledger {
        guard data.count <= 100_000_000 else { throw LedgerError.invalid("备份文件超过 100 MB，已停止导入。") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let ledger = try decoder.decode(Ledger.self, from: data)
        try ledger.validate()
        return ledger
    }
}

public enum LedgerFiles {
    /// Stage in the destination directory, then rename. Existing files are never replaced.
    public static func createNew(_ data: Data, at destination: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw LedgerError.invalid("目标文件已存在，不会覆盖。") }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".qingledger-stage-\(UUID().uuidString)")
        defer { if manager.fileExists(atPath: stage.path) { try? manager.removeItem(at: stage) } }
        try data.write(to: stage, options: .atomic)
        try manager.moveItem(at: stage, to: destination)
    }
}

/// A failed load is surfaced to the UI and never silently replaced with an empty ledger.
public struct LedgerRepository {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("ledger.qingledger") }
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> Ledger? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try LedgerCodec.decode(Data(contentsOf: file))
    }
    public func save(_ ledger: Ledger, preserveImportSnapshot: Bool = false) throws {
        let data = try LedgerCodec.encode(ledger)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        if manager.fileExists(atPath: file.path) {
            let backups = directory.appendingPathComponent("Backups", isDirectory: true)
            try manager.createDirectory(at: backups, withIntermediateDirectories: true)
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = .current
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let daily = backups.appendingPathComponent("daily-\(dateFormatter.string(from: .now)).qingledger")
            if !manager.fileExists(atPath: daily.path) { try manager.copyItem(at: file, to: daily) }
            if preserveImportSnapshot {
                let backup = backups.appendingPathComponent("before-import-\(UUID().uuidString).qingledger")
                try manager.copyItem(at: file, to: backup)
            }
            let previous = try Data(contentsOf: file)
            #if os(iOS)
            try previous.write(to: backups.appendingPathComponent("last-good.qingledger"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try previous.write(to: backups.appendingPathComponent("last-good.qingledger"), options: .atomic)
            #endif
        }
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
    }
}

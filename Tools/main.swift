import Foundation
import LedgerCore

do {
    let args = CommandLine.arguments
    guard args.count == 4, args[1] == "migrate" else {
        throw LedgerError.invalid("用法：swift run LedgerTool migrate /path/database.sql /path/output.qingledger")
    }
    let source = URL(fileURLWithPath: args[2]), destination = URL(fileURLWithPath: args[3])
    let report = destination.appendingPathExtension("migration-report.json")
    guard !FileManager.default.fileExists(atPath: destination.path), !FileManager.default.fileExists(atPath: report.path), source.standardizedFileURL != destination.standardizedFileURL else {
        throw LedgerError.invalid("输出文件已存在，或与原文件相同；不会覆盖。")
    }
    let (ledger, summary) = try MoneyProImporter.read(source)
    try LedgerFiles.createNew(LedgerCodec.encode(ledger), at: destination)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let reportData = try encoder.encode(summary)
    try LedgerFiles.createNew(reportData, at: report)
    FileHandle.standardOutput.write(reportData)
    print("")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}

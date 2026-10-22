import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import LedgerCore
#endif

struct SettingsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var importing = false
    @State private var exporting = false
    @State private var document = BackupDocument(data: Data())
    @State private var newCategory = false
    @State private var title = ""
    @State private var exportMessage: String?
    var body: some View {
        Form {
            Section("我的账本") {
                TextField("账本名称", text: $title)
                Button("保存名称") { _ = store.commit { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) } }
                LabeledContent("记录", value: "\(store.ledger.entries.count) 笔")
                LabeledContent("货币", value: "人民币 CNY（第一版）")
            }
            Section {
                Button("导出完整备份", systemImage: "square.and.arrow.up") {
                    do { document = BackupDocument(data: try LedgerCodec.encode(store.ledger)); exporting = true }
                    catch { store.error = error.localizedDescription }
                }
                Button("导入 Centwise 备份 / Money Pro 数据库", systemImage: "square.and.arrow.down") { importing = true }
                Text(".qingledger 备份包含全部 Centwise 数据和旧账本原字段归档。导入前会显示预览并询问是否替换，不会操作手机里的 Money Pro。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("数据由你掌握") }
            footer: { Text("备份是明文财务数据，建议保存在加密磁盘。无云同步，删除应用仍可能丢失本机数据，请定期导出。Backups 保留最近一次修改前、每天第一笔修改前和导入前的快照；第一版不自动清理每日/导入快照。") }
            Section("分类管理") {
                NavigationLink("查看与新增分类") { categories }
            }
            if let legacy = store.ledger.legacy {
                Section("Money Pro 迁移说明") {
                    ForEach(Array(legacy.warnings.enumerated()), id: \.offset) { Text($0.element).font(.caption).foregroundStyle(.secondary) }
                    Text("原字段归档不随新账单修改；不代表旧应用可反向恢复。未接入旧 iCloud 同步。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("关于 Centwise") {
                LabeledContent("版本", value: "0.1 · 自用 MVP")
                Text("独立实现 · SwiftUI · 无第三方依赖 · 本地优先")
                Text("已实现收支、转账、分摊、账户、分类、月预算与报表。循环交易、票据附件、外币、云同步和 App Store 上架暂未实现。")
                    .font(.caption).foregroundStyle(.secondary)
                #if os(macOS)
                Text("本地目录：\(store.repository.directory.path)").font(.caption).textSelection(.enabled)
                #endif
            }
        }.ledgerFormBackground().navigationTitle("设置与备份")
            .onAppear { title = store.ledger.title }
            .onChange(of: store.ledger.title) { _, value in title = value }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .json], allowsMultipleSelection: false) { result in
                switch result { case .success(let urls): if let url = urls.first { store.prepareImport(url) }
                case .failure(let error): if (error as NSError).code != NSUserCancelledError { store.error = error.localizedDescription } }
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: BackupDocument.contentType,
                          defaultFilename: "Centwise备份-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                switch result { case .success: exportMessage = "已导出完整备份，请保存在可信位置。"
                case .failure(let error): if (error as NSError).code != NSUserCancelledError { store.error = error.localizedDescription } }
            }
            .alert("备份已保存", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                Button("好", role: .cancel) { exportMessage = nil }
            } message: { Text(exportMessage ?? "") }
    }
    private var categories: some View {
        List {
            ForEach([EntryKind.expense, .income]) { kind in
                Section(kind.title) {
                    ForEach(store.ledger.categories.filter { $0.kind == kind }) { category in
                        Label(category.name, systemImage: category.symbol)
                    }
                }
            }
            Button("添加分类", systemImage: "plus.circle") { newCategory = true }
        }.ledgerFormBackground().navigationTitle("分类").sheet(isPresented: $newCategory) { CategoryEditor().environmentObject(store) }
    }
}

private struct CategoryEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var kind = EntryKind.expense
    @State private var icon = "square.grid.2x2"
    let icons = ["square.grid.2x2", "fork.knife", "tram.fill", "bag.fill", "house.fill", "heart.fill", "sparkles", "briefcase.fill", "gift.fill", "book.fill"]
    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)
                Picker("类型", selection: $kind) { Text("支出").tag(EntryKind.expense); Text("收入").tag(EntryKind.income) }.pickerStyle(.segmented)
                Picker("图标", selection: $icon) { ForEach(icons, id: \.self) { Label($0, systemImage: $0).tag($0) } }
            }.ledgerFormBackground().navigationTitle("新分类").inlineTitle().toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let category = LedgerCategory(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, symbol: icon)
                        if store.commit({ $0.categories.append(category) }) { dismiss() }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.editorFrame(minHeight: 320)
    }
}

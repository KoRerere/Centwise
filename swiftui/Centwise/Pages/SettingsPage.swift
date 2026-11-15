import SwiftUI
import UniformTypeIdentifiers

let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.3.0"

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// 设置与备份.
struct SettingsSheet: View {
    @Environment(LedgerStore.self) private var store
    @State private var exporting = false
    @State private var exportDocument: BackupDocument?
    @State private var importing = false
    @State private var pickingCurrency = false
    @State private var editingCategories = false
    @State private var pickingTheme = false
    @State private var pickingLanguage = false
    @State private var alert: CwAlert?
    @State private var closing = false
    @Environment(\.dismiss) private var dismiss

    static func themeLabel(_ m: ThemeMode) -> String {
        switch m { case .system: tr("自动"); case .dark: tr("深色"); case .light: tr("浅色") }
    }

    static func languageLabel(_ p: LanguagePref) -> String {
        switch p { case .system: tr("跟随系统"); case .zhHans: "简体中文"; case .zhHant: "繁體中文"; case .en: "English" }
    }

    private var exportName: String {
        let p = Cal.parts(Date())
        return "\(tr("Centwise备份"))-\(String(format: "%04d-%02d-%02d", p.year, p.month, p.day))"
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try LedgerCodec.encode(store.ledger))
            exporting = true
        } catch {
            store.error = "\(error)"
        }
    }

    var body: some View {
        SheetScaffold(title: tr("设置与备份"), largeTitle: true, closeButton: false) {
            ScrollView {
                VStack(spacing: 28) {
                    SheetLargeTitle(title: tr("设置与备份")).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, -28)
                    FormSection {
                        FormRow(icon: "receipt", label: tr("记录")) { Text(tr("{n} 笔", ["n": store.ledger.entries.count])) }
                        FormRow(icon: "coins", label: tr("货币"), chevron: true, onTap: { pickingCurrency = true }) { CurrencyLabel(code: store.ledger.currency) }
                    }
                    FormSection {
                        HStack(spacing: 0) {
                            FormIconTile("cloud-off")
                            Spacer().frame(width: FormMetrics.textInset - FormIconTile.size)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("账本保存在本机")).cw(IOSText.body, .semibold)
                                Text(tr("iCloud 同步暂未开放")).cw(IOSText.footnote, color: .cwMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .containerValue(\.dividerInset, FormMetrics.textInset)
                        FormRow(icon: "upload", label: tr("导出完整备份"), onTap: export)
                        FormRow(icon: "download", label: tr("导入备份或 Money Pro 数据"), onTap: { importing = true })
                        FormRow(icon: "info", label: tr("了解更多"), chevron: true, onTap: {
                            alert = CwAlert.info(title: tr("关于备份"), message:
                                tr(".centwise 备份包含全部 Centwise 数据和旧账本原字段归档；也可以导入 SwiftUI 版导出的 .qingledger 备份。导入前会显示预览并询问是否替换，不会操作手机里的 Money Pro。\n\n")
                                + tr("备份是明文财务数据，建议保存在加密磁盘。无云同步，删除应用仍可能丢失本机数据，请定期导出。Backups 保留最近一次修改前、每天第一笔修改前和导入前的快照；第一版不自动清理每日/导入快照。"))
                        })
                    }
                    FormSection {
                        FormRow(icon: "layout-grid", label: tr("编辑分类"), chevron: true, onTap: { editingCategories = true })
                        FormRow(icon: "sun-moon", label: tr("外观"), chevron: true, onTap: { pickingTheme = true }) { Text(Self.themeLabel(store.themeMode)) }
                        FormRow(icon: "languages", label: tr("应用语言"), chevron: true, onTap: { pickingLanguage = true }) { Text(Self.languageLabel(store.languagePref)) }
                        FormRow(icon: "refresh-cw", label: tr("检查更新"), onTap: {
                            alert = CwAlert.info(title: tr("检查更新"), message: tr("当前版本 {version}。Centwise 目前是开发版，还没有接入在线更新；新版本会直接安装到你的设备上。", ["version": appVersion]))
                        }) { Text(tr("当前版本：{version}", ["version": appVersion])) }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 32)
            }
            .sheetScroll()
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                // Pulling the list down past its top closes 设置 (its list fills the sheet).
                if y < -64 && !closing { closing = true; Haptics.selection(); dismiss() }
            }
        }
        // 设置 opens with a swipe right on 概览 and closes with the reverse swipe.
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            let dx = value.translation.width, vx = value.predictedEndTranslation.width - dx
            if !closing && abs(dx) > abs(value.translation.height) && (dx < -70 || vx < -200) {
                closing = true; Haptics.selection(); dismiss()
            }
        })
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .data, defaultFilename: exportName + ".centwise") { result in
            if case .success = result { alert = CwAlert.info(title: tr("备份已保存"), message: tr("已导出完整备份，请保存在可信位置。")) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item, .json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            store.prepareImport(url)
        }
        .cwSheet(isPresented: $pickingCurrency) { CurrencyPicker() }
        .cwSheet(isPresented: $editingCategories) { CategoriesSheet() }
        .cwSheet(isPresented: $pickingTheme, height: 300, style: .card) {
            OptionSheet(caption: tr("外观"), current: store.themeMode,
                        options: [(.system, tr("自动（跟随系统）")), (.light, tr("浅色")), (.dark, tr("深色"))]) { store.setThemeMode($0) }
        }
        .cwSheet(isPresented: $pickingLanguage, height: 350, style: .card) {
            OptionSheet(caption: tr("应用语言"), current: store.languagePref, options: LanguagePref.allCases.map { ($0, Self.languageLabel($0)) }) {
                store.setLanguage($0)
            }
        }
        .cwAlert($alert)
    }
}

/// A short list of options with the current one checked.
struct OptionSheet<T: Hashable>: View {
    @Environment(\.dismiss) private var dismiss
    let caption: String
    let current: T
    let options: [(T, String)]
    let onPick: (T) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.cwTrack).frame(width: 38, height: 5).padding(.top, 8)
            Text(caption).cw(IOSText.footnote, color: .cwMuted).padding(.top, 16).padding(.bottom, 8)
            ForEach(options, id: \.0) { value, title in
                Pressable(onTap: { onPick(value); dismiss() }) {
                    HStack(spacing: 6) {
                        Text(title).cw(IOSText.headline, value == current ? .bold : .regular, color: value == current ? .cwAccent : .cwInk)
                        if value == current { LIcon("check", size: 18, color: .cwAccent, strokeWidth: 2.5) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }
}

/// 货币: one currency per ledger, no conversion.
struct CurrencyPicker: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        let current = store.ledger.currency
        SheetScaffold(title: tr("货币"), leadingLabel: tr("完成")) {
            ScrollView {
                FormSection(footer: tr("账本只用一种货币。切换后只改变显示的货币符号，已记录的金额不会换算。")) {
                    ForEach(supportedCurrencies, id: \.code) { c in
                        Pressable(onTap: {
                            guard c.code != current else { return }
                            Haptics.selection()
                            store.setCurrency(c.code)
                        }) {
                            HStack(spacing: 12) {
                                FlagIcon(code: c.flag, size: 26)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(c.name).cw(IOSText.body)
                                    Text("\(c.code) · \(c.symbol)").cw(IOSText.footnote, color: .cwMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if c.code == current { LIcon("check", size: 18, color: .cwAccent, strokeWidth: 2.5) }
                            }
                            .frame(minHeight: 54)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 32)
            }
            .sheetScroll()
        }
    }
}

struct CategoryEditRequest: Identifiable {
    let id = newID()
    var category: LedgerCategory?
    var kind: EntryKind?
    var parentID: String?
}

/// 编辑分类: expense and income grids; categories with a number open their subcategories.
struct CategoriesSheet: View {
    @Environment(LedgerStore.self) private var store
    @State private var parent: LedgerCategory?
    @State private var direction: CGFloat = 1
    @State private var editing: CategoryEditRequest?

    private func back() {
        direction = -1
        withAnimation(PushMotion.animation) { parent = nil }
    }

    var body: some View {
        let ledger = store.ledger
        let current = parent.flatMap { ledger.category($0.id) }
        SheetScaffold(title: current?.name ?? tr("分类"), leadingLabel: current == nil ? tr("完成") : tr("返回"), onLeading: current == nil ? nil : back) {
            ZStack {
                if let current {
                    subcategories(current).id("sub-\(current.id)").transition(PushMotion.transition(direction))
                } else {
                    overview.id("top").transition(PushMotion.transition(direction))
                }
            }
            .clipped()
        }
        .cwSheet(item: $editing) { req in CategoryEditor(editing: req.category, initialKind: req.kind, initialParentID: req.parentID) }
    }

    private var overview: some View {
        let ledger = store.ledger
        return ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([EntryKind.expense, .income], id: \.self) { kind in
                        caption(kind.title)
                        CategoryGrid {
                            ForEach(ledger.categories.filter { $0.kind == kind && ledger.isTopLevel($0) }) { c in tile(c, drill: true) }
                            addTile { editing = CategoryEditRequest(kind: kind) }
                        }
                        Spacer().frame(height: 22)
                    }
                    Text(tr("点分类可以改名、换图标或调整上级分类；带数字的分类有子分类，点开查看。改名不影响已有账单。"))
                        .cw(IOSText.footnote, color: .cwMuted).lineSpacing(3).padding(.horizontal, 16)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
            }
            .sheetScroll()
    }

    private func caption(_ text: String) -> some View {
        Text(text).cw(IOSText.footnote, color: .cwMuted).padding(.leading, 16).padding(.bottom, 10)
    }

    private func tile(_ c: LedgerCategory, drill: Bool) -> some View {
        let children = store.ledger.children(of: c.id).count
        return CategoryGridTile(name: c.name, badge: drill && children > 0 ? "\(children)" : nil, onTap: {
            if drill && children > 0 { Haptics.selection(); direction = 1; withAnimation(PushMotion.animation) { parent = c } } else { editing = CategoryEditRequest(category: c) }
        }) { CategoryIcon(c, size: 24) }
    }

    private func addTile(_ onTap: @escaping () -> Void) -> some View {
        CategoryGridTile(name: tr("添加"), onTap: onTap) { LIcon("plus", size: 22) }
    }

    private func subcategories(_ p: LedgerCategory) -> some View {
        let parent = store.ledger.category(p.id) ?? p
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormSection {
                    Pressable(onTap: { editing = CategoryEditRequest(category: parent) }) {
                        HStack(spacing: 12) {
                            CategoryIcon(parent, size: 24)
                            Text(tr("编辑「{name}」", ["name": parent.name])).cw(IOSText.body).frame(maxWidth: .infinity, alignment: .leading)
                            LIcon("chevron-right", size: 14, color: .cwMuted.opacity(0.6))
                        }
                        .frame(minHeight: FormMetrics.minHeight)
                    }
                }
                Spacer().frame(height: 22)
                caption(tr("子分类"))
                CategoryGrid {
                    ForEach(store.ledger.children(of: parent.id)) { c in tile(c, drill: false) }
                    addTile { editing = CategoryEditRequest(kind: parent.kind, parentID: parent.id) }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
        }
        .sheetScroll()
    }
}

/// 新分类 / 编辑分类: name, parent, emoji icon.
struct CategoryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: LedgerCategory?
    @State private var name: String
    @State private var kind: EntryKind
    @State private var icon: String
    @State private var parentID: String?
    @State private var pickingParent = false

    init(editing: LedgerCategory? = nil, initialKind: EntryKind? = nil, initialParentID: String? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _kind = State(initialValue: editing?.kind ?? initialKind ?? .expense)
        _icon = State(initialValue: editing.map(categoryIcon) ?? categoryIconChoices[0])
        _parentID = State(initialValue: editing == nil ? initialParentID : editing!.parentID)
    }

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let hasChildren = editing != nil && !store.ledger.children(of: editing!.id).isEmpty
        let parent = store.ledger.category(parentID)
        let changed = editing == nil || trimmed != editing!.name || icon != categoryIcon(editing!) || parentID != editing!.parentID
        SheetScaffold(title: editing == nil ? tr("新分类") : tr("编辑分类"), trailingLabel: tr("保存"), onTrailing: trimmed.isEmpty || !changed ? nil : save) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if editing == nil {
                        CapsuleSegments(values: [EntryKind.expense, .income], selected: kind, label: \.title) { kind = $0; parentID = nil }
                            .padding(.bottom, 18)
                    }
                    FormSection {
                        HStack(spacing: 10) {
                            EmojiIcon(icon, size: 22)
                            FormTextField(text: $name, hint: tr("分类名称"))
                        }
                        if !hasChildren {
                            FormRow(label: tr("上级分类"), chevron: true, onTap: { pickingParent = true }) { Text(parent?.name ?? tr("无")) }
                        }
                    }
                    CardCaption(tr("图标")).padding(.top, 18).padding(.bottom, 10)
                    EmojiPicker(selected: emojiFor(icon), common: categoryIconChoices.map { categoryEmojiMap[$0]! }) { icon = iconKeyForEmoji($0) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 32)
            }
            .sheetScroll()
            .scrollDismissesKeyboard(.immediately)
        }
        .cwSheet(isPresented: $pickingParent) {
            CategoryChooser(kind: kind, selectedID: parentID ?? "", title: tr("上级分类"), leadingLabel: tr("无"), leadingIcon: "circle-x",
                            topLevelOnly: true, excludeID: editing?.id, showAdd: false, onPick: { parentID = $0.isEmpty ? nil : $0 })
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let ok = store.commit { ledger in
            if let editing {
                guard let i = ledger.categories.firstIndex(where: { $0.id == editing.id }) else { return }
                ledger.categories[i].name = trimmed
                ledger.categories[i].symbol = icon
                ledger.categories[i].parentID = parentID
            } else {
                ledger.categories.append(LedgerCategory(name: trimmed, kind: kind, symbol: icon, parentID: parentID))
            }
        }
        if ok { dismiss() }
    }
}

/// "先核对，再导入".
struct ImportPreview: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetScaffold(title: tr("导入预览"), onLeading: { store.cancelImport(); dismiss() }) {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 36)).foregroundStyle(Color.cwAccent)
                    Text(tr("先核对，再导入")).cw(24, .bold).padding(.top, 14)
                    CwCard { Text(store.importDescription).cw(15).lineSpacing(5).textSelection(.enabled) }.padding(.top, 18)
                    Text(store.isDemo ? tr("预览模式只替换内存中的账本，退出后不保存。原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。")
                         : tr("这是替换导入，不是合并。当前 Centwise 账本会先自动保存一份本地备份；原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。"))
                        .cw(13, color: .cwMuted).lineSpacing(5).padding(.top, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PrimaryBarButton(label: tr("确认替换当前账本")) {
                        store.confirmImport()
                        if store.pendingImport == nil { dismiss() }
                    }
                    .padding(.top, 18)
                }
                .padding(24)
            }
            .sheetScroll()
        }
    }
}

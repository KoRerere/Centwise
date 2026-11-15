import SwiftUI

/// A category in a grid: a white disc with its emoji, a check badge when picked, or a count badge.
struct CategoryGridTile<Icon: View>: View {
    let name: String
    var checked = false
    var badge: String?
    /// Edit mode: a small pencil badge; tapping opens the category's editor.
    var editBadge = false
    var nameColor: Color = .cwMuted
    var nameWeight: Font.Weight = .regular
    /// false: the emoji alone, no white disc (the disc only comes back to mark the picked one).
    var disc = true
    let onTap: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Pressable(onTap: onTap) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(disc || checked ? Color.cwCard : .clear)
                        .overlay(Circle().stroke(checked ? Color.cwInk : .clear, lineWidth: 1.5))
                        .frame(width: 48, height: 48)
                    icon()
                }
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) {
                    if editBadge {
                        Circle().fill(Color.cwInk)
                            .overlay(Circle().stroke(Color.cwCanvas, lineWidth: 2))
                            .frame(width: 20, height: 20)
                            .overlay(Image(systemName: "pencil").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.cwOnBrand))
                            .transition(.scale.combined(with: .opacity))
                    } else if checked {
                        Circle().fill(Color.cwInk)
                            .overlay(Circle().stroke(Color.cwCanvas, lineWidth: 2))
                            .frame(width: 18, height: 18)
                            .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color.cwOnBrand))
                    } else if let badge {
                        Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color.cwMuted))
                            .overlay(Capsule().stroke(Color.cwCanvas, lineWidth: 2))
                            .offset(x: 2, y: -1)
                    }
                }
                Text(name).cw(IOSText.footnote, nameWeight, color: nameColor).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Grid of category tiles: 5 columns on a phone.
struct CategoryGrid<Content: View>: View {
    var columns = 5
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns), spacing: 10) { content() }
    }
}

/// The 记一笔 / 订阅 category strip: pages of 5 × 2 top-level categories with page dots.
struct CategoryPager: View {
    let categories: [LedgerCategory]
    /// The chosen category (may be a subcategory: its parent tile shows as picked, with its name).
    let chosen: LedgerCategory?
    let hasChildren: (LedgerCategory) -> Bool
    let onTap: (LedgerCategory) -> Void
    @State private var page = 0

    var body: some View {
        let pages = max(1, Int(ceil(Double(categories.count) / 10)))
        VStack(spacing: 12) {
            TabView(selection: $page) {
                ForEach(0..<pages, id: \.self) { p in
                    VStack(spacing: 14) {
                        ForEach([0, 5], id: \.self) { r in
                            HStack(alignment: .top, spacing: 8) {
                                ForEach(0..<5, id: \.self) { c in
                                    let index = p * 10 + r + c
                                    if index < categories.count { tile(categories[index]) } else { Color.clear.frame(height: 76) }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(p)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 172)
            if pages > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule().fill(i == page ? Color.cwInk : Color.cwMuted.opacity(0.35))
                            .frame(width: i == page ? 16 : 6, height: 6)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: page)
            }
        }
    }

    private func tile(_ category: LedgerCategory) -> some View {
        let selected = chosen != nil && (chosen!.id == category.id || chosen!.parentID == category.id)
        let label = selected && chosen!.id != category.id ? chosen!.name : category.name
        return CategoryGridTile(name: label, checked: selected, nameColor: selected ? .cwInk : .cwMuted, nameWeight: selected ? .bold : .regular,
                                disc: false, onTap: { onTap(category) }) {
            CategoryIcon(category, size: selected ? 26 : 32)
        }
        .selectPop(selected)
        .frame(height: 76)
    }
}

/// Picks one category: a grid of top-level categories; ones with subcategories open a list.
struct CategoryChooser: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let kind: EntryKind
    let selectedID: String
    var title: String?
    /// A first tile meaning "none / all" (picks ""), e.g. 全部支出.
    var leadingLabel: String?
    var leadingIcon = "layout-grid"
    var parentSubtitle: String?
    var topLevelOnly = false
    var excludeID: String?
    var showAdd = true
    /// Open straight at this category's subcategories; going back then closes the chooser.
    var initialParentID: String?
    let onPick: (String) -> Void

    @State private var query = ""
    @State private var parent: LedgerCategory?
    @State private var direction: CGFloat = 1
    @State private var placed = false
    @State private var addingCategory = false
    @State private var addingSub: CategoryEditRequest?
    /// 编辑 mode: tiles open the category's editor instead of picking it.
    @State private var editingMode = false
    @State private var editingCategory: CategoryEditRequest?
    @FocusState private var searchFocus: Bool

    private var ledger: Ledger { store.ledger }

    private func all() -> [LedgerCategory] {
        ledger.categories.filter { $0.kind == kind && $0.id != excludeID && (!topLevelOnly || ledger.isTopLevel($0)) }
    }

    private func pick(_ id: String) {
        onPick(id)
        dismiss()
    }

    private func edit(_ c: LedgerCategory) {
        Haptics.selection()
        editingCategory = CategoryEditRequest(category: c)
    }

    private var backCloses: Bool { initialParentID != nil && parent?.id == initialParentID }

    private func open(_ c: LedgerCategory) {
        Haptics.selection()
        direction = 1
        withAnimation(PushMotion.animation) { parent = c }
    }

    private func back() {
        if backCloses { dismiss(); return }
        direction = -1
        withAnimation(PushMotion.animation) { parent = nil }
    }

    var body: some View {
        let current = parent.flatMap { ledger.category($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces)
        SheetScaffold(title: current?.name ?? title ?? tr("选择分类"), leadingLabel: current == nil ? nil : tr("返回"),
                      onLeading: current == nil ? nil : back) {
            VStack(spacing: 0) {
                searchRow
                ZStack {
                    if !q.isEmpty {
                        searchResults.transition(.opacity)
                    } else if let current {
                        subList(current).id("sub-\(current.id)").transition(PushMotion.transition(direction))
                    } else {
                        topLevel.id("top").transition(PushMotion.transition(direction))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
            }
        }
        .onAppear {
            if !placed { placed = true; parent = ledger.category(initialParentID) }
        }
        .cwSheet(isPresented: $addingCategory) { CategoryEditor(initialKind: kind) }
        .cwSheet(item: $addingSub) { req in CategoryEditor(initialKind: req.kind, initialParentID: req.parentID) }
        .cwSheet(item: $editingCategory) { req in CategoryEditor(editing: req.category) }
    }

    private var searchResults: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let found = all().filter { $0.name.lowercased().contains(q) }
        return ScrollView {
            rowsCard(found.map { c in
                RowSpec(category: c, title: c.parentID == nil ? c.name : "\(ledger.category(c.parentID)?.name ?? "") › \(c.name)",
                        checked: !editingMode && c.id == selectedID, chevron: editingMode,
                        action: { if editingMode { edit(c) } else { pick(c.id) } })
            })
            .padding(.horizontal, 16).padding(.bottom, 32)
        }
        .sheetScroll()
        .scrollDismissesKeyboard(.immediately)
    }

    /// Same search capsule as 账单, with the 编辑 entry after it.
    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                LucideIcon(name: "search", size: 18, color: .cwMuted)
                TextField("", text: $query, prompt: Text(tr("搜索分类")).foregroundStyle(Color.cwMuted))
                    .font(.cw(IOSText.body)).foregroundStyle(Color.cwInk)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocus)
                    .padding(.leading, 10)
                if !query.isEmpty {
                    Pressable(onTap: { query = "" }) { LIcon("circle-x", size: 18, color: .cwMuted).padding(4) }
                        .accessibilityLabel(tr("清除搜索"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(Capsule().fill(Color.cwSurface))
            if showAdd {
                Pressable(onTap: {
                    Haptics.selection()
                    searchFocus = false
                    withAnimation(IOSMotion.snappy) { editingMode.toggle() }
                }) {
                    Group {
                        if editingMode {
                            Text(tr("完成")).cw(IOSText.body, .semibold, color: .cwOnBrand)
                                .padding(.horizontal, 18).frame(height: 50)
                                .background(Capsule().fill(Color.cwBrand))
                        } else {
                            Text(tr("编辑")).cw(IOSText.body, .medium)
                                .padding(.horizontal, 18).frame(height: 50)
                                .background(Capsule().fill(Color.cwSurface))
                        }
                    }
                }
                .accessibilityLabel(editingMode ? tr("完成") : tr("编辑分类"))
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 22)
    }

    private var topLevel: some View {
        let selected = ledger.category(selectedID)
        let selectedTop = selected?.parentID ?? selected?.id
        return ScrollView {
            VStack(spacing: 0) {
                CategoryGrid {
                    if let leadingLabel {
                        CategoryGridTile(name: leadingLabel, checked: selectedID.isEmpty, onTap: { pick("") }) {
                            LIcon(leadingIcon, size: 22)
                        }
                    }
                    ForEach(all().filter { ledger.isTopLevel($0) }) { c in
                        let hasChildren = !topLevelOnly && !ledger.children(of: c.id).isEmpty
                        // In 编辑 mode a category with subcategories still opens its list (to reach them);
                        // the others open their editor.
                        CategoryGridTile(name: c.name, checked: !editingMode && selectedTop == c.id,
                                         badge: editingMode && hasChildren ? "\(ledger.children(of: c.id).count)" : nil,
                                         editBadge: editingMode && !hasChildren, onTap: {
                            if hasChildren { open(c) } else if editingMode { edit(c) } else { pick(c.id) }
                        }) { CategoryIcon(c, size: 24) }
                    }
                    if showAdd {
                        CategoryGridTile(name: tr("新增分类"), onTap: { addingCategory = true }) { LIcon("plus", size: 22) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 32)
        }
        .sheetScroll()
        .scrollDismissesKeyboard(.immediately)
    }

    /// A category's subcategories, laid out in the same grid as the top level. The first tile is the
    /// category itself (不细分); in 编辑 mode every tile opens its editor.
    private func subList(_ parent: LedgerCategory) -> some View {
        ScrollView {
            VStack(spacing: 18) {
            parentHeader(parent)
            CategoryGrid {
                // The category itself (不细分); in 编辑 mode it is edited from the header above instead.
                if !editingMode {
                    CategoryGridTile(name: parentSubtitle ?? tr("不细分"), checked: selectedID == parent.id, onTap: { pick(parent.id) }) {
                        CategoryIcon(parent, size: 24)
                    }
                }
                ForEach(ledger.children(of: parent.id)) { c in
                    CategoryGridTile(name: c.name, checked: !editingMode && c.id == selectedID, editBadge: editingMode, onTap: {
                        if editingMode { edit(c) } else { pick(c.id) }
                    }) { CategoryIcon(c, size: 24) }
                }
                if showAdd {
                    CategoryGridTile(name: tr("新增分类"), onTap: {
                        addingSub = CategoryEditRequest(kind: kind, parentID: parent.id)
                    }) { LIcon("plus", size: 22) }
                }
            }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .sheetScroll()
        .scrollDismissesKeyboard(.immediately)
    }

    /// The first-level category this page belongs to, with a way to edit it.
    private func parentHeader(_ parent: LedgerCategory) -> some View {
        Pressable(onTap: { edit(parent) }) {
            HStack(spacing: 12) {
                CategoryIcon(parent, size: 26)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.cwCanvas))
                VStack(alignment: .leading, spacing: 2) {
                    Text(parent.name).cw(IOSText.body, .semibold).lineLimit(1)
                    Text(tr("{n} 个子分类", ["n": ledger.children(of: parent.id).count])).cw(IOSText.footnote, color: .cwMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    LIcon("pencil", size: 14, color: .cwInk)
                    Text(tr("编辑")).cw(IOSText.subheadline, .semibold)
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(Color.cwTrack))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.cwCard))
        }
        .accessibilityLabel(tr("编辑一级分类"))
    }

    struct RowSpec: Identifiable {
        var id: String { category.id + title }
        let category: LedgerCategory
        let title: String
        var subtitle: String?
        let checked: Bool
        let chevron: Bool
        let action: () -> Void
    }

    private func rowsCard(_ rows: [RowSpec]) -> some View {
        CwCard(h: 16, v: 2) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Rectangle().fill(Color.cwStroke).frame(height: hairline).padding(.leading, 35) }
                    Pressable(onTap: row.action) {
                        HStack(spacing: 12) {
                            CategoryIcon(row.category, size: 20)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.title).cw(IOSText.body).lineLimit(1)
                                if let subtitle = row.subtitle { Text(subtitle).cw(IOSText.footnote, color: .cwMuted).lineLimit(1) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if row.checked { LIcon("check", size: 17, color: .cwAccent, strokeWidth: 2.5).padding(.trailing, 6) }
                            if row.chevron { LIcon("chevron-right", size: 14, color: .cwMuted.opacity(0.6)) }
                        }
                        .frame(minHeight: 50)
                    }
                }
                if rows.isEmpty {
                    Text(tr("没有匹配的分类")).cw(IOSText.subheadline, color: .cwMuted).padding(.vertical, 16).frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Height for a chooser opened straight at a category's subcategories.
func subcategorySheetHeight(_ ledger: Ledger, _ parentID: String) -> CGFloat {
    let children = ledger.children(of: parentID).count
    let bottom = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first?.safeAreaInsets.bottom) ?? 34
    // Grid: the category itself, its children and the 新增分类 tile, five to a row.
    let rows = CGFloat((children + 2 + 4) / 5)
    return 148 + 86 + rows * 82 + 40 + bottom
}

/// Wheel date picker with 今天 / 完成, shown as a short sheet.
struct DateWheelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: Date
    var minimum: Date = Cal.date(1970, 1, 1)
    var maximum: Date = Cal.date(2099, 12, 31)
    let onDone: (Date) -> Void
    @State private var picked = Date()
    @State private var placed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(tr("今天")) {
                    let now = Cal.parts(Date()), p = Cal.parts(picked)
                    onDone(Cal.date(now.year, now.month, now.day, p.hour, p.minute, p.second))
                    dismiss()
                }
                Spacer()
                Button(tr("完成")) { onDone(picked); dismiss() }
            }
            .font(.system(size: 17))
            .tint(.cwInk)
            .padding(.horizontal, 12).padding(.top, 6)
            DatePicker("", selection: $picked, in: minimum...maximum, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, L10n.locale)
                .frame(maxHeight: .infinity)
        }
        .onAppear { if !placed { picked = initial; placed = true } }
    }
}

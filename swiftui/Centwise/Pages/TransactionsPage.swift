import SwiftUI

/// 账单: search, type filter, bills grouped by day in one long card. Also used inside a sheet for one
/// category's bills (`categoryID`).
struct TransactionsPage: View {
    @Environment(LedgerStore.self) private var store
    var searchRequest: Binding<Bool>?
    var categoryID: String?
    var includeSubcategories = true

    @State private var query = ""
    @State private var kind: EntryKind?
    @State private var allDates = false
    @State private var editing: Entry?
    @FocusState private var searchFocus: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let (start, end) = store.interval
        let q = trimmedQuery.lowercased()
        let ids: Set<String>? = categoryID.map { includeSubcategories ? store.ledger.subtreeIDs($0) : [$0] }
        let filtered = store.ledger.entries.filter { e in
            if !allDates && (e.date < start || e.date >= end) { return false }
            if let ids, !e.allocations.contains(where: { ids.contains($0.categoryID) }) { return false }
            if let kind, e.kind != kind { return false }
            if q.isEmpty { return true }
            return "\(e.note) \(e.payee) \(store.categoryName(e)) \(store.accountName(e.accountID))".lowercased().contains(q)
        }.sorted { $0.date > $1.date }
        func amountOf(_ e: Entry) -> Int {
            guard let ids else { return e.amount }
            return e.allocations.filter { ids.contains($0.categoryID) }.reduce(0) { $0 + $1.amount }
        }
        let total = filtered.filter { !$0.pending && (kind != nil || categoryID != nil || $0.kind == .expense) }.reduce(0) { $0 + amountOf($1) }

        return ScrollView {
            VStack(spacing: 16) {
                searchCard
                card(filtered, total: total)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .modifier(ContentTransition(trigger: "\(store.period)|\(store.month.timeIntervalSinceReferenceDate)"))
        }
        .sheetScroll()
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: store.interval.0) { allDates = false }
        .onChange(of: searchRequest?.wrappedValue ?? false) { _, requested in
            guard requested else { return }
            searchRequest?.wrappedValue = false
            allDates = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { searchFocus = true }
        }
        .cwSheet(item: $editing) { EntryEditor(entry: $0) }
    }

    private var heading: String {
        if allDates { return tr("全部日期") }
        switch store.period {
        case .day:
            let label = DayHeading.label(store.month)
            return label == tr("今天") || label == tr("昨天") ? tr("{date} {day}", ["date": fmtMonthDay(store.month), "day": label]) : label
        case .month: return fmtYearMonth(store.month)
        case .year: return store.periodName
        }
    }

    private var totalLabel: String {
        if let kind { return kind.title }
        if categoryID != nil { return tr("该分类") }
        if allDates { return tr("全部日期支出") }
        return tr("{period}支出", ["period": store.period == .day ? tr("当天", ctx: "period") : store.periodWord])
    }

    private func headerRows(_ count: Int, _ total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline) {
                Text(heading).cw(19, .bold).frame(maxWidth: .infinity, alignment: .leading)
                AmountText(cents: total, size: 20, weight: .bold, sign: "").fixedSize()
            }
            if store.period != .day || allDates {
                HStack {
                    Text(tr("{n} 笔 · 合计为{label}", ["n": count, "label": totalLabel])).cw(IOSText.footnote, color: .cwMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if allDates {
                        Pressable(onTap: { allDates = false }) {
                            Text(tr("只看{scope}", ["scope": store.periodName])).cw(IOSText.footnote, .semibold, color: .cwAccent)
                        }
                    }
                }
            }
        }
    }

    private func card(_ filtered: [Entry], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRows(filtered.count, total)
            if filtered.isEmpty {
                let emptyLabel: String = {
                    if !trimmedQuery.isEmpty {
                        return allDates ? tr("全部日期中没有找到“{query}”", ["query": trimmedQuery])
                            : tr("{scope}没有找到“{query}”", ["scope": store.periodName, "query": trimmedQuery])
                    }
                    if allDates { return tr("还没有符合条件的账单") }
                    switch store.period {
                    case .day: return tr("这一天没有符合条件的账单")
                    case .month: return tr("这个月没有符合条件的账单")
                    case .year: return tr("今年没有符合条件的账单")
                    }
                }()
                EmptyState(icon: "folder-search", title: emptyLabel, illustration: trimmedQuery.isEmpty ? "receipt" : "search")
                    .padding(.horizontal, -20)
                    .padding(.top, 20)
                    .frame(minHeight: 300)
                if kind != nil {
                    Pressable(onTap: { kind = nil }) { Text(tr("清除筛选")).cw(IOSText.subheadline, .semibold, color: .cwAccent) }
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
                if !trimmedQuery.isEmpty && !allDates {
                    Pressable(onTap: { allDates = true }) { Text(tr("改为搜索全部日期")).cw(IOSText.subheadline, .semibold, color: .cwAccent) }
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedByDay(filtered), id: \.0) { day, items in
                        DayHeadingView(day: day).padding(.top, 18).padding(.bottom, 2)
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                            if i > 0 { RowDivider() }
                            EntryRow(entry: entry, onTap: { editing = entry })
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: filtered.isEmpty ? 360 : 0, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color.cwCard))
    }

    private var searchCard: some View {
        HStack(spacing: 0) {
            LucideIcon(name: "search", size: 18, color: .cwMuted)
            TextField("", text: $query, prompt: Text(tr("搜索")).foregroundStyle(Color.cwMuted))
                .font(.cw(IOSText.body)).foregroundStyle(Color.cwInk)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocus)
                .padding(.leading, 10)
            if !query.isEmpty {
                Pressable(onTap: { query = "" }) { LIcon("circle-x", size: 18, color: .cwMuted).padding(4) }
                    .accessibilityLabel(tr("清除搜索"))
            }
            if let kind, categoryID == nil {
                Pressable(onTap: { self.kind = nil }) {
                    HStack(spacing: 3) {
                        Text(kind.title).cw(IOSText.footnote, .semibold)
                        LIcon("x", size: 13, color: .cwMuted, strokeWidth: 2.5)
                    }
                    .padding(.leading, 10).padding(.trailing, 7).frame(height: 28)
                    .background(Capsule().fill(Color.cwTrack))
                }
                .accessibilityLabel(tr("清除筛选"))
                .padding(.trailing, 8)
            }
            if categoryID == nil { filterMenu }
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(Capsule().fill(Color.cwSurface))
    }

    private var filterMenu: some View {
        let entries = store.ledger.entries
        var kinds: [EntryKind?] = [nil, .expense, .income]
        for k in [EntryKind.transfer, .adjustment] where k == kind || entries.contains(where: { $0.kind == k }) { kinds.append(k) }
        return Menu {
            Picker("", selection: Binding(get: { kind }, set: { kind = $0 })) {
                ForEach(kinds, id: \.self) { k in Text(k?.title ?? tr("全部")).tag(k) }
            }
        } label: {
            LIcon("list-filter", size: 18, color: kind == nil ? .cwMuted : .cwAccent, strokeWidth: kind == nil ? 2 : 2.5)
                .padding(.leading, 6)
                .frame(height: 44)
        }
        .accessibilityLabel(tr("按类型筛选"))
    }
}

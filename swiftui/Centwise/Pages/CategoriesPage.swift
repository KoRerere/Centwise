import SwiftUI

private struct CategoryLine: Identifiable {
    var id: String { category.id + (directOnly ? "#direct" : "") }
    let category: LedgerCategory
    let spent: Int
    let budget: Budget?
    var directOnly = false
}

private struct CategoryGroup { let head: CategoryLine; let children: [CategoryLine] }

/// Identifiable wrapper for sheets about one category.
struct CategorySheetRequest: Identifiable {
    let id = newID()
    let category: LedgerCategory
    var includeSubcategories = true
    var title: String?
}

struct BudgetRequest: Identifiable {
    let id = newID()
    var budget: Budget?
    var categoryID: String?
}

/// 分类: share donut, category grid, month budget, six-month trend.
struct CategoriesPage: View {
    @Environment(LedgerStore.self) private var store
    @State private var openedCategory: CategorySheetRequest?
    @State private var budgetRequest: BudgetRequest?

    var body: some View {
        let ledger = store.ledger
        let spending = store.periodCategorySpending
        let monthBudgets = ledger.budgets(for: store.month)
        var spentByID: [String: Int] = [:]
        for (c, v) in spending { spentByID[c.id] = v }
        var budgetByID: [String: Budget] = [:]
        for b in monthBudgets { if let id = b.categoryID { budgetByID[id] = b } }
        func subtreeSpent(_ id: String) -> Int { ledger.subtreeIDs(id).reduce(0) { $0 + (spentByID[$1] ?? 0) } }
        func line(_ c: LedgerCategory, _ spent: Int, directOnly: Bool = false) -> CategoryLine {
            CategoryLine(category: c, spent: spent, budget: directOnly ? nil : budgetByID[c.id], directOnly: directOnly)
        }
        func byAmount(_ a: CategoryLine, _ b: CategoryLine) -> Bool { a.spent == b.spent ? a.category.name < b.category.name : a.spent > b.spent }
        var groups: [CategoryGroup] = []
        for top in ledger.categories where top.kind == .expense && ledger.isTopLevel(top) {
            var children = ledger.children(of: top.id).filter { subtreeSpent($0.id) != 0 || budgetByID[$0.id] != nil }.map { line($0, subtreeSpent($0.id)) }.sorted(by: byAmount)
            let direct = spentByID[top.id] ?? 0
            if !children.isEmpty && direct != 0 { children.append(line(top, direct, directOnly: true)) }
            let head = line(top, subtreeSpent(top.id))
            if head.spent == 0 && head.budget == nil && children.isEmpty { continue }
            groups.append(CategoryGroup(head: head, children: children))
        }
        groups.sort { byAmount($0.head, $1.head) }
        let emptyText: String = switch store.period {
        case .day: tr("这一天还没有支出")
        case .month: tr("本月还没有支出")
        case .year: tr("今年还没有支出")
        }
        let topSpending = ledger.topLevelSpending(in: store.entries(in: store.interval))
        var tints: [String: Color] = [:]
        for (i, item) in topSpending.enumerated() { tints[item.0.id] = categoryPalette[i % categoryPalette.count] }
        let mp = Cal.parts(store.month)
        let trendMonths = (-5...0).map { Cal.date(mp.year, mp.month + $0, 1) }

        return PageList {
            PeriodSummary(spending: topSpending, tints: tints, emptyText: emptyText)
            if !groups.isEmpty {
                VStack(spacing: 10) {
                    CwCard(h: 14, v: 18) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 5), spacing: 8) {
                            ForEach(groups.map(\.head)) { line in
                                Pressable(onTap: {
                                    openedCategory = CategorySheetRequest(category: line.category, includeSubcategories: !line.directOnly,
                                                                          title: line.directOnly ? tr("{name} · 未细分", ["name": line.category.name]) : nil)
                                }, onLongPress: { budgetRequest = BudgetRequest(budget: line.budget, categoryID: line.category.id) }) {
                                    VStack(spacing: 0) {
                                        Circle().fill(Color.cwCanvas).frame(width: 52, height: 52).overlay(CategoryIcon(line.category, size: 26))
                                        HStack(spacing: 4) {
                                            Circle().fill(tints[line.category.id] ?? .cwMuted).frame(width: 6, height: 6)
                                            Text(line.category.name).cw(12, .medium).lineLimit(1)
                                        }
                                        .padding(.top, 5)
                                        AmountText(cents: line.spent, size: 12, weight: .semibold).padding(.top, 2)
                                    }
                                    .frame(height: 104)
                                }
                                .accessibilityLabel(line.category.name)
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Pressable(onTap: { budgetRequest = BudgetRequest(categoryID: groups.first?.head.category.id) }) {
                            HStack(spacing: 3) {
                                LIcon("plus", size: 14, color: .cwAccent, strokeWidth: 2.5)
                                Text(tr("分类预算")).cw(IOSText.footnote, .semibold, color: .cwAccent)
                            }
                        }
                    }
                }
            }
            MonthBudgetCard()
            VStack(alignment: .leading, spacing: 10) {
                CardCaption(tr("近六个月"))
                CwCard {
                    TrendChart(labels: trendMonths.map(fmtMonth), titles: trendMonths.map(fmtYearMonth),
                               income: trendMonths.map { ledger.total(.income, $0) }, expense: trendMonths.map { ledger.total(.expense, $0) })
                }
            }
        }
        .cwSheet(item: $openedCategory) { req in
            SheetScaffold(title: req.title ?? req.category.name, leadingLabel: tr("完成")) {
                TransactionsPage(categoryID: req.category.id, includeSubcategories: req.includeSubcategories)
            }
        }
        .cwSheet(item: $budgetRequest) { req in BudgetEditor(budget: req.budget, categoryID: req.categoryID) }
    }
}

/// Donut of the period's spending by top-level category, with the top three listed.
private struct PeriodSummary: View {
    @Environment(LedgerStore.self) private var store
    let spending: [(LedgerCategory, Int)]
    let tints: [String: Color]
    let emptyText: String

    var body: some View {
        let slices = spending.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let total = slices.reduce(0) { $0 + $1.1 }
        if total <= 0 {
            CwCard(padding: .all(0)) {
                EmptyState(icon: "piggy-bank", title: emptyText, illustration: "wallet", message: tr("有支出后，这里会按分类显示占比"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            let periodLabel = store.isCurrentPeriod ? store.periodWord : store.periodName
            CwCard(20) {
                HStack(spacing: 20) {
                    DonutChart(slices: slices.map { (Double($0.1), tints[$0.0.id] ?? categoryTint($0.0.id)) })
                        .accessibilityLabel(tr("{period}支出分类占比", ["period": periodLabel]))
                    VStack(alignment: .leading, spacing: 0) {
                        AmountText(cents: total, size: 22, weight: .bold)
                        Text(tr("{period}支出", ["period": periodLabel])).cw(IOSText.footnote, color: .cwMuted).padding(.top, 2)
                        VStack(spacing: 4) {
                            ForEach(slices.prefix(3), id: \.0.id) { category, value in
                                row(tints[category.id] ?? categoryTint(category.id), category.name, .cwInk, percent(value, total))
                            }
                            if slices.count > 3 {
                                row(Color.cwMuted.opacity(0.5), tr("其他 {n} 类", ["n": slices.count - 3]), .cwMuted,
                                    percent(slices.dropFirst(3).reduce(0) { $0 + $1.1 }, total))
                            }
                        }
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private func percent(_ v: Int, _ total: Int) -> String {
        let value = Double(v) * 100 / Double(total)
        return value < 1 ? "<1%" : "\(Int(value.rounded()))%"
    }

    private func row(_ dot: Color, _ name: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(name).cw(IOSText.footnote, color: color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(value).cw(IOSText.footnote, color: .cwMuted)
        }
    }
}

/// {month}预算: the total budget (or the sum of category budgets) with spent / remaining.
private struct MonthBudgetCard: View {
    @AppStorage(BudgetPrompt.key) private var hiddenUntil: Double = 0
    @Environment(LedgerStore.self) private var store
    @State private var editing = false

    var body: some View {
        let ledger = store.ledger
        let totalBudget = ledger.budget(for: nil, store.month)
        let monthBudgets = ledger.budgets(for: store.month)
        let categorySum = monthBudgets.filter { $0.categoryID != nil }.reduce(0) { $0 + $1.limit }
        let limit = totalBudget?.limit ?? (categorySum > 0 ? categorySum : nil)
        let caption = tr("{month}预算", ["month": fmtYearMonth(store.month)])
        Group {
            if let limit {
                let spent = totalBudget.map { ledger.spent($0, store.month) }
                    ?? monthBudgets.filter { $0.categoryID != nil }.reduce(0) { $0 + ledger.spent($1, store.month) }
                let remaining = limit - spent
                let ratio = Double(spent) / Double(limit <= 0 ? 1 : limit)
                Pressable(onTap: { editing = true }) {
                    VStack(alignment: .leading, spacing: 10) {
                        CardCaption(totalBudget == nil ? "\(caption) · \(tr("分类预算合计"))" : caption, trailing: tr("调整预算"), onTap: { editing = true })
                        BudgetFigures(spent: spent, limit: limit, remaining: remaining, ratio: ratio, overLabel: tr("超出预算"), overRed: true)
                    }
                }
            } else if !BudgetPrompt.isHidden(hiddenUntil) {
                VStack(alignment: .leading, spacing: 10) {
                    CardCaption(caption)
                    BudgetSetupCard { editing = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .cwSheet(isPresented: $editing) { BudgetEditor(budget: totalBudget) }
    }
}

/// 已花 / 预算 / 剩余 with a bar.
struct BudgetFigures: View {
    let spent: Int
    let limit: Int
    let remaining: Int
    let ratio: Double
    var overLabel = tr("超出")
    var overRed = false

    var body: some View {
        CwCard {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    metric(tr("已花")) { AmountText(cents: spent, size: IOSText.body, weight: .semibold) }
                    metric(tr("预算")) { AmountText(cents: limit, size: IOSText.body, weight: .semibold) }
                    metric(remaining < 0 ? overLabel : tr("剩余")) {
                        HStack(spacing: 4) {
                            AmountText(cents: abs(remaining), size: IOSText.body, weight: .semibold, sign: "", color: remaining < 0 && overRed ? .cwOver : .cwInk)
                            Circle().fill(remaining < 0 ? Color.cwOver : .cwUnder).frame(width: 6, height: 6)
                        }
                    }
                }
                BudgetBar(ratio: ratio, height: 8).padding(.top, 14)
                BudgetUsageLine(ratio: ratio).padding(.top, 8)
            }
        }
    }

    private func metric<V: View>(_ title: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(spacing: 4) {
            Text(title).cw(IOSText.footnote, color: .cwMuted)
            value()
        }
        .frame(maxWidth: .infinity)
    }
}

/// 月度总预算 / {分类}预算 card on 概览.
struct BudgetCard: View {
    @Environment(LedgerStore.self) private var store
    let budget: Budget
    @State private var editing = false

    var body: some View {
        let spent = store.ledger.spent(budget, store.month)
        let remaining = budget.limit - spent
        let ratio = Double(spent) / Double(budget.limit <= 0 ? 1 : budget.limit)
        let name = budget.categoryID == nil ? tr("月度总预算") : tr("{name}预算", ["name": store.category(budget.categoryID)?.name ?? tr("分类")])
        let title = budget.month == nil ? name : "\(name) · \(tr("仅 {month}", ["month": fmtYearMonth(budget.month!.date)]))"
        Pressable(onTap: { editing = true }) {
            VStack(alignment: .leading, spacing: 10) {
                CardCaption(title, trailing: tr("调整预算"), onTap: { editing = true })
                BudgetFigures(spent: spent, limit: budget.limit, remaining: remaining, ratio: ratio)
            }
        }
        .cwSheet(isPresented: $editing) { BudgetEditor(budget: budget) }
    }
}

/// "这个月还没有预算 · 设定".
/// Long-pressing the 设定预算 prompt lets it be put away for a while (today / this week / this month).
enum BudgetPrompt {
    static let key = "budgetPromptHiddenUntil"

    enum Snooze: CaseIterable { case today, week, month }

    /// When a snooze chosen now ends: tomorrow, next Monday, or the 1st of next month.
    static func until(_ snooze: Snooze, from now: Date = Date()) -> Date {
        let p = Cal.parts(now)
        switch snooze {
        case .today: return Cal.date(p.year, p.month, p.day + 1)
        case .week:
            // weekday is 1 = Monday … 7 = Sunday; the week ends at next Monday 00:00.
            return Cal.date(p.year, p.month, p.day + 8 - p.weekday)
        case .month: return Cal.date(p.year, p.month + 1, 1)
        }
    }

    static func isHidden(_ hiddenUntil: Double) -> Bool { Date().timeIntervalSinceReferenceDate < hiddenUntil }
}

struct BudgetSetupCard: View {
    @Environment(LedgerStore.self) private var store
    @AppStorage(BudgetPrompt.key) private var hiddenUntil: Double = 0
    let onTap: () -> Void

    var body: some View {
        Pressable(onTap: onTap) {
            CwCard(padding: .lrtb(16, 16, 16, 14)) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        FormIconTile("piggy-bank")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr("这个月还没有预算")).cw(IOSText.body, .semibold)
                            Text(tr("设定每月上限，随时知道还能花多少")).cw(IOSText.footnote, color: .cwMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(tr("设定")).cw(IOSText.subheadline, .semibold, color: .cwOnBrand)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(Capsule().fill(Color.cwBrand))
                    }
                    RoundedRectangle(cornerRadius: 3).fill(Color.cwTrack).frame(height: 6).padding(.top, 14)
                    HStack {
                        Text(tr("本月已支出")).cw(IOSText.footnote, color: .cwMuted)
                        Spacer()
                        AmountText(cents: store.ledger.total(.expense, store.month), size: IOSText.footnote, weight: .semibold, sign: "", color: .cwMuted, brand: false)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Section(tr("暂时收起预算提醒")) {
                Button { snooze(.today) } label: { Label(tr("今天不再提醒"), systemImage: "sun.max") }
                Button { snooze(.week) } label: { Label(tr("本周不再提醒"), systemImage: "calendar") }
                Button { snooze(.month) } label: { Label(tr("本月不再提醒"), systemImage: "moon.zzz") }
            }
        }
    }

    private func snooze(_ s: BudgetPrompt.Snooze) {
        Haptics.selection()
        let until = BudgetPrompt.until(s).timeIntervalSinceReferenceDate
        // Let the menu close first, then fold the card away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(IOSMotion.smooth) { hiddenUntil = until }
        }
    }
}

/// 新预算 / 编辑预算.
struct BudgetEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let budget: Budget?
    @State private var categoryID: String
    @State private var thisMonthOnly: Bool
    @State private var amount: String
    @State private var choosingScope = false
    @State private var confirmDelete = false
    @State private var alert: CwAlert?

    init(budget: Budget? = nil, categoryID: String? = nil) {
        self.budget = budget
        _categoryID = State(initialValue: budget?.categoryID ?? categoryID ?? "")
        _thisMonthOnly = State(initialValue: budget?.month != nil)
        _amount = State(initialValue: budget.map { Money.input($0.limit) } ?? "")
    }

    private var amountError: String? {
        let text = amount.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return nil }
        guard let cents = try? Money.parse(text) else { return tr("请输入有效金额") }
        return cents <= 0 ? tr("预算需大于 0；不需要这项预算可以删除") : nil
    }

    private var canSave: Bool { !amount.trimmingCharacters(in: .whitespaces).isEmpty && amountError == nil }

    private func save() {
        do {
            let target: String? = categoryID.isEmpty ? nil : categoryID
            let month: YearMonth? = thisMonthOnly ? YearMonth(store.month) : nil
            func sameScope(_ b: Budget) -> Bool { b.categoryID == target && (b.month == nil ? month == nil : month != nil && b.applies(to: month!)) }
            let keepOriginal = budget != nil && budget!.month == nil && month != nil
            let slot = store.ledger.budgets.first(where: sameScope)
            let new = Budget(id: slot?.id ?? (budget != nil && !keepOriginal ? budget!.id : newID()), categoryID: target,
                             limit: try Money.parse(amount.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".")), month: month)
            let original = budget
            let apply: (inout Ledger) -> Void = { ledger in
                ledger.budgets.removeAll { $0.id == new.id }
                if let original, !keepOriginal, original.id != new.id { ledger.budgets.removeAll { $0.id == original.id } }
                ledger.budgets.append(new)
            }
            var test = store.ledger
            apply(&test)
            try test.validate()
            if store.commit({ apply(&$0) }) { dismiss() }
        } catch {
            alert = CwAlert.info(title: tr("请检查输入"), message: (error as? LedgerError)?.message ?? "\(error)")
        }
    }

    private var scopeFooter: String {
        if categoryID.isEmpty { return tr("统计当月所有支出，和各分类预算分开计算，不会相加。") }
        let name = store.category(categoryID)?.name ?? tr("分类")
        return store.ledger.children(of: categoryID).isEmpty ? tr("只统计「{name}」的支出。", ["name": name]) : tr("统计「{name}」及其所有子分类的支出。", ["name": name])
    }

    var body: some View {
        SheetScaffold(title: budget == nil ? tr("新预算") : tr("编辑预算"), trailingLabel: tr("保存"), onTrailing: canSave ? save : nil) {
            ScrollView {
                VStack(spacing: 0) {
                    CapsuleSegments(values: [true, false], selected: thisMonthOnly, label: { $0 ? tr("本月预算") : tr("每月预算") }) { thisMonthOnly = $0 }
                    Text(thisMonthOnly ? tr("只在 {month} 生效，这个月会替代每月预算。", ["month": fmtYearMonth(store.month)])
                         : tr("每个月自动生效；某个月另设了本月预算时，以本月预算为准。"))
                        .cw(IOSText.footnote, color: .cwMuted).multilineTextAlignment(.center).padding(.top, 8)
                    FormSection(footer: scopeFooter) {
                        FormRow(icon: "chart-pie", label: tr("范围"), chevron: true, onTap: { choosingScope = true }) {
                            Text(categoryID.isEmpty ? tr("全部支出") : store.ledger.children(of: categoryID).isEmpty
                                 ? store.category(categoryID)?.name ?? tr("分类")
                                 : tr("{name}（含子分类）", ["name": store.category(categoryID)?.name ?? tr("分类")]))
                                .frame(maxWidth: 190, alignment: .trailing)
                        }
                        LabeledField(icon: "coins", label: tr("预算金额（{code}）", ["code": store.ledger.currency]),
                                     text: Binding(get: { amount }, set: { if let v = sanitizeMoneyInput($0) { amount = v } }),
                                     hint: tr("例如 3000"), keyboard: .decimalPad, error: amountError, alignEnd: true)
                    }
                    .padding(.top, 18)
                    if budget != nil {
                        FormSection { FormRow(icon: "trash", label: tr("删除预算"), destructive: true, onTap: { confirmDelete = true }) }
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 32)
            }
            .sheetScroll()
        }
        .cwSheet(isPresented: $choosingScope) {
            CategoryChooser(kind: .expense, selectedID: categoryID, title: tr("选择范围"), leadingLabel: tr("全部支出"), parentSubtitle: tr("含子分类"),
                            showAdd: false, onPick: { categoryID = $0 })
        }
        .confirmationDialog("", isPresented: $confirmDelete) {
            Button(tr("删除预算"), role: .destructive) {
                if store.commit({ l in l.budgets.removeAll { $0.id == budget?.id } }) { dismiss() }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: { Text(tr("删除这项预算？不会删除账单。")) }
        .cwAlert($alert)
    }
}

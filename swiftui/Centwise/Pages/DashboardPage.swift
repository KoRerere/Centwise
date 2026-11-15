import SwiftUI

/// A tab page: a vertical list of cards that fades and drifts slightly when the period changes.
struct PageList<Content: View>: View {
    @Environment(LedgerStore.self) private var store
    var spacing: CGFloat = 26
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .modifier(ContentTransition(trigger: "\(store.period)|\(store.month.timeIntervalSinceReferenceDate)"))
        }
    }
}

struct DashboardPage: View {
    @Environment(LedgerStore.self) private var store
    let onShowTransactions: () -> Void
    let onNewEntry: () -> Void
    @State private var editingBudget = false
    @AppStorage(BudgetPrompt.key) private var hiddenUntil: Double = 0

    var body: some View {
        let ledger = store.ledger
        let totalBudget = ledger.budget(for: nil, store.month)
        PageList {
            if store.period == .year { YearCard() } else { SpendCard() }
            if ledger.entries.isEmpty {
                CwCard(padding: .hv(18, 28)) {
                    VStack(spacing: 0) {
                        LIcon("pencil", size: 30, color: .cwMuted)
                        Text(tr("从今天的第一笔开始")).cw(IOSText.headline, .bold).padding(.top, 10)
                        Text(tr("点右下角加号记下收支，或在设置里导入旧账本。")).cw(IOSText.footnote, color: .cwMuted).multilineTextAlignment(.center).padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if store.period == .year {
                YearCategoryGrid()
            } else {
                RecentCard(onShowTransactions: onShowTransactions, onNewEntry: onNewEntry)
            }
            if let totalBudget {
                BudgetCard(budget: totalBudget)
            } else if !BudgetPrompt.isHidden(hiddenUntil) {
                BudgetSetupCard { editingBudget = true }
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .cwSheet(isPresented: $editingBudget) { BudgetEditor() }
    }
}

/// 今日 / 本月支出: total, comparison with the same point of the previous period, cumulative chart.
struct SpendCard: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        let series = SpendSeries.of(store)
        let difference = series.currentTotal - series.previousAtSameStep
        let over = difference > 0
        let isDay = store.period == .day
        let comparison: String = {
            if difference == 0 { return isDay ? (store.isCurrentPeriod ? tr("与昨天同期持平") : tr("与前一天同期持平")) : tr("与上月同期持平") }
            if isDay {
                return store.isCurrentPeriod ? (over ? tr("比昨天同期多花 {amount}") : tr("比昨天同期少花 {amount}"))
                    : (over ? tr("比前一天同期多花 {amount}") : tr("比前一天同期少花 {amount}"))
            }
            return over ? tr("比上月同期多花 {amount}") : tr("比上月同期少花 {amount}")
        }()
        let start = store.interval.0
        let sp = Cal.parts(start)
        let ticks = isDay ? ["00:00", "12:00", "24:00"]
            : [fmtMonthDay(start), fmtMonthDay(Cal.date(sp.year, sp.month, 15)), fmtMonthDay(Cal.date(sp.year, sp.month + 1, 0))]
        let periodLabel = store.isCurrentPeriod ? store.periodWord : store.periodName
        CwCard(padding: .lrtb(20, 18, 20, 16)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("{period}支出", ["period": periodLabel])).cw(IOSText.footnote, color: .cwMuted)
                AmountText(cents: series.currentTotal, size: 34, weight: .bold).padding(.top, 4)
                HStack(spacing: 4) {
                    if difference != 0 { LIcon(over ? "arrow-up-right" : "arrow-down-left", size: 14, color: over ? .cwOver : .cwUnder, strokeWidth: 2.5) }
                    TextWithAmount(template: comparison, cents: abs(difference), amountColor: difference == 0 ? nil : (over ? .cwOver : .cwUnder))
                }
                .padding(.top, 4)
                CumulativeChart(current: series.current, previous: series.previous, domainMax: series.steps, ticks: ticks)
                    .padding(.top, 14)
                    .accessibilityLabel(isDay ? tr("今天累计支出走势，虚线为昨天") : tr("本月累计支出走势，虚线为上月"))
                HStack(spacing: 5) {
                    legendLine(.cwBrand, dashed: false)
                    Text(periodLabel).cw(IOSText.footnote, color: .cwMuted)
                    Spacer().frame(width: 9)
                    legendLine(Color.cwMuted.opacity(0.7), dashed: true)
                    Text(isDay ? (store.isCurrentPeriod ? tr("昨天") : tr("前一天")) : tr("上月")).cw(IOSText.footnote, color: .cwMuted)
                }
                .padding(.top, 8)
            }
        }
    }

    private func legendLine(_ color: Color, dashed: Bool) -> some View {
        HStack(spacing: 2) { ForEach(0..<(dashed ? 3 : 1), id: \.self) { _ in Rectangle().fill(color).frame(height: 2) } }.frame(width: 16, height: 2)
    }
}

struct SpendSeries {
    let current: [Double]
    let previous: [Double]
    let currentTotal: Int
    let previousAtSameStep: Int
    let steps: Int

    static func of(_ store: LedgerStore) -> SpendSeries {
        let isDay = store.period == .day
        let start = store.interval.0, previousStart = store.previousInterval.0
        let count = isDay ? 25 : Cal.daysInMonth(start)
        let previousCount = isDay ? 25 : Cal.daysInMonth(previousStart)
        func bucket(_ d: Date) -> Int { isDay ? Cal.hour(d) + 1 : Cal.day(d) - 1 }
        func perStep(_ range: (Date, Date), _ length: Int) -> [Int] {
            var values = [Int](repeating: 0, count: length)
            for e in store.entries(in: range) where e.kind == .expense {
                let i = bucket(e.date)
                if i >= 0 && i < length { values[i] += e.amount }
            }
            return values
        }
        let now = Date()
        let thisSteps = perStep(store.interval, count)
        var lastStep = store.isCurrentPeriod ? (isDay ? Cal.hour(now) + 1 : Cal.day(now) - 1) : count - 1
        var i = count - 1
        while i > lastStep {
            if thisSteps[i] != 0 { lastStep = i; break }
            i -= 1
        }
        let lastSteps = perStep(store.previousInterval, previousCount)
        var current: [Double] = []
        var running = 0
        for j in 0..<min(lastStep + 1, count) {
            running += thisSteps[j]
            current.append(Double(running) / 100)
        }
        let currentTotal = running
        var previous: [Double] = []
        running = 0
        var atSame = 0
        for j in 0..<previousCount {
            running += lastSteps[j]
            previous.append(Double(running) / 100)
            if j == (lastStep < previousCount ? lastStep : previousCount - 1) { atSame = running }
        }
        return SpendSeries(current: current, previous: previous, currentTotal: currentTotal, previousAtSameStep: atSame, steps: count)
    }
}

/// 今年: total, monthly bars against the average, and yearly figures.
struct YearCard: View {
    @Environment(LedgerStore.self) private var store

    var body: some View {
        let months = store.yearMonths
        let total = months.reduce(0) { $0 + $1.expense }
        let incomeTotal = months.reduce(0) { $0 + $1.income }
        let average = store.monthlyAverage(.expense)
        let averageIncome = store.monthlyAverage(.income)
        let highlight = months.firstIndex { Cal.sameMonth($0.month, store.month) } ?? -1
        VStack(alignment: .leading, spacing: 0) {
            CwCard(20) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("{period}支出", ["period": store.isCurrentPeriod ? store.periodWord : store.periodName])).cw(IOSText.footnote, color: .cwMuted)
                    AmountText(cents: total, size: 34, weight: .bold).padding(.top, 4)
                    TextWithAmount(template: tr("平均每月 {amount}"), cents: average).padding(.top, 4)
                    MonthBarsChart(values: months.map(\.expense), labels: months.map { "\(Cal.month($0.month))" }, average: average, highlight: highlight)
                        .padding(.top, 14)
                        .accessibilityLabel(tr("今年每月支出，虚线为月均"))
                    Text("\(store.yearRangeText) · \(tr("深色高于月均，浅色低于月均"))").cw(IOSText.caption1, color: .cwMuted).padding(.top, 8)
                }
            }
            CardCaption(tr("年度指标"), trailing: tr("按 {n} 个月平均", ["n": store.averageMonthCount])).padding(.top, 18)
            CwCard(h: 16, v: 2) {
                VStack(spacing: 0) {
                    metric(tr("今年总支出"), total, .cwInk)
                    Rectangle().fill(Color.cwStroke).frame(height: hairline)
                    metric(tr("平均每月支出"), average, .cwInk)
                    Rectangle().fill(Color.cwStroke).frame(height: hairline)
                    metric(tr("今年总收入"), incomeTotal, .cwIncome)
                    Rectangle().fill(Color.cwStroke).frame(height: hairline)
                    metric(tr("平均每月结余"), averageIncome - average, averageIncome - average >= 0 ? .cwIncome : .cwOver)
                }
            }
            .padding(.top, 8)
        }
    }

    private func metric(_ title: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Text(title).cw(IOSText.body).frame(maxWidth: .infinity, alignment: .leading)
            AmountText(cents: value, size: IOSText.body, weight: .medium, color: color).fixedSize()
        }
        .padding(.vertical, 11)
    }
}

/// 今年 spending by top-level category, as a grid; tap to see its bills.
struct YearCategoryGrid: View {
    @Environment(LedgerStore.self) private var store
    @State private var opened: LedgerCategory?

    var body: some View {
        let spending = store.ledger.topLevelSpending(in: store.entries(in: store.interval)).filter { $0.1 > 0 }
        VStack(alignment: .leading, spacing: 8) {
            CardCaption(tr("分类支出"), trailing: tr("共 {n} 类", ["n": spending.count]))
            CwCard(padding: .lrtb(10, 14, 10, 6)) {
                if spending.isEmpty {
                    Text(tr("今年还没有支出")).cw(IOSText.subheadline, color: .cwMuted).frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 4), spacing: 0) {
                        ForEach(spending, id: \.0.id) { category, amount in
                            Pressable(onTap: { opened = category }) {
                                VStack(spacing: 0) {
                                    Circle().fill(Color.cwCanvas).frame(width: 44, height: 44).overlay(CategoryIcon(category, size: 26))
                                    Text(category.name).cw(IOSText.footnote, color: .cwMuted).lineLimit(1).padding(.top, 6)
                                    AmountText(cents: amount, size: 13, weight: .semibold).padding(.horizontal, 4).padding(.top, 2)
                                }
                                .padding(.bottom, 14)
                            }
                            .accessibilityLabel(tr("{name}的账单", ["name": category.name]))
                        }
                    }
                }
            }
        }
        .cwSheet(item: $opened) { c in
            SheetScaffold(title: c.name, leadingLabel: tr("完成")) { TransactionsPage(categoryID: c.id) }
        }
    }
}

/// 最近账单: the last few bills of the period.
struct RecentCard: View {
    @Environment(LedgerStore.self) private var store
    let onShowTransactions: () -> Void
    let onNewEntry: () -> Void
    @State private var editing: Entry?

    var body: some View {
        let entries = store.periodEntries
        let empty: String = switch store.period {
        case .day: tr("这一天还没有记录")
        case .month: tr("这个月还没有记录")
        case .year: tr("今年还没有记录")
        }
        VStack(alignment: .leading, spacing: 8) {
            CardCaption(tr("最近账单"), trailing: entries.isEmpty ? nil : tr("共 {n} 笔消费", ["n": entries.count]), onTap: onShowTransactions)
            CwCard(padding: entries.isEmpty ? .all(0) : .hv(14, 8)) {
                if entries.isEmpty {
                    EmptyState(icon: "receipt", title: empty, illustration: "receipt",
                               message: store.isCurrentPeriod ? tr("花了什么、收了什么，随手记一笔") : nil,
                               actionLabel: store.loadingFailed ? nil : tr("记一笔"), onAction: onNewEntry)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    VStack(spacing: 0) {
                        ForEach(groupedByDay(Array(entries.prefix(6))), id: \.0) { day, items in
                            DayHeadingView(day: day).padding(.top, 10).padding(.bottom, 2)
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, entry in
                                if i > 0 { RowDivider() }
                                EntryRow(entry: entry, onTap: { editing = entry })
                            }
                        }
                    }
                }
            }
        }
        .cwSheet(item: $editing) { EntryEditor(entry: $0) }
    }
}

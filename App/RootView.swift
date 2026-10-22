import SwiftUI
import Charts
#if SWIFT_PACKAGE
import LedgerCore
#endif

/// Top-level pages, shown as Copilot-style pill tabs under the brand title.
enum CentwisePage: Int, CaseIterable, Identifiable, Hashable {
    case dashboard, categories, transactions, accounts
    var id: Int { rawValue }
    var title: String {
        switch self { case .dashboard: "概览"; case .categories: "分类"; case .transactions: "账单"; case .accounts: "账户" }
    }
}

struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var page: CentwisePage = .dashboard
    @State private var newEntry = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas.ignoresSafeArea()
            Theme.headerGradient.frame(height: 320).frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                if store.isDemo || store.loadingFailed {
                    Text(store.isDemo ? "预览模式 · 初始为演示数据 · 退出后不保存修改" : "账本读取失败 · 原文件已保留 · 写入已暂停")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(Color.black.opacity(0.25))
                }
                header
                pageTabs
                pages
            }
        }
        .overlay(alignment: .bottom) { floatingControls }
        .sheet(isPresented: $newEntry) { EntryEditor().environmentObject(store) }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showSettings = false } }
                    }
            }
            .environmentObject(store)
            .tint(Theme.accent)
            .storeAlerts(store, enabled: true)
            .editorFrame(minHeight: 640)
        }
        // While Settings is open it presents these itself; one presenter at a time.
        .storeAlerts(store, enabled: !showSettings)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            headerButton("gearshape", label: "设置与备份") { showSettings = true }
            Spacer()
            Text("Centwise").font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Spacer()
            headerButton("magnifyingglass", label: "搜索账单") {
                withAnimation(.easeInOut(duration: 0.25)) { page = .transactions }
            }
        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.92)).frame(width: 40, height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label)
    }

    private var pageTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CentwisePage.allCases) { item in
                        let selected = item == page
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { page = item }
                        } label: {
                            Text(item.title)
                                .font(.system(size: 15, weight: selected ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(selected ? 1 : 0.62))
                                .padding(.horizontal, 16).frame(height: 34)
                                .background { if selected { Capsule().fill(Color.white.opacity(0.16)) } }
                                .overlay { if selected { Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1) } }
                                .contentShape(Capsule())
                        }.buttonStyle(.plain).id(item)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("navigation.\(item.rawValue)")
                    }
                }.padding(.horizontal, 16).frame(maxWidth: .infinity)
            }
            .onChange(of: page) { _, value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
        }.padding(.bottom, 12)
    }

    @ViewBuilder private var pages: some View {
        #if os(iOS)
        // Swipe between pages, like Copilot.
        TabView(selection: $page) {
            ForEach(CentwisePage.allCases) { item in
                pageView(item).tag(item)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        pageView(page).frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    @ViewBuilder private func pageView(_ item: CentwisePage) -> some View {
        switch item {
        case .dashboard: OverviewView(showTransactions: { withAnimation { page = .transactions } })
        case .categories: InsightsView()
        case .transactions: TransactionsView()
        case .accounts: AccountsView()
        }
    }

    // MARK: Floating controls

    private var floatingControls: some View {
        ZStack {
            if page != .accounts { MonthCapsule() }
            HStack {
                Spacer()
                FloatingCircleButton(symbol: "plus", label: "记一笔") { newEntry = true }
                    .disabled(store.loadingFailed)
                    .accessibilityIdentifier("entry.new")
            }
        }.padding(.horizontal, 18).padding(.bottom, 10)
    }
}

// MARK: - Store alerts & import preview

struct StoreAlerts: ViewModifier {
    @ObservedObject var store: LedgerStore
    let enabled: Bool
    func body(content: Content) -> some View {
        content
            .alert("操作未完成", isPresented: Binding(get: { enabled && store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("知道了", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .sheet(isPresented: Binding(get: { enabled && store.pendingImport != nil }, set: { if !$0 { store.pendingImport = nil } })) {
                ImportPreview().environmentObject(store)
            }
    }
}

extension View {
    func storeAlerts(_ store: LedgerStore, enabled: Bool) -> some View {
        modifier(StoreAlerts(store: store, enabled: enabled))
    }
}

struct ImportPreview: View {
    @EnvironmentObject var store: LedgerStore
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 40, weight: .medium)).foregroundStyle(Theme.accent)
                    Text("先核对，再导入").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                    Text(store.importDescription).font(.system(size: 15, design: .rounded)).foregroundStyle(Theme.ink)
                        .textSelection(.enabled).ledgerCard()
                    Text(store.isDemo ? "预览模式只替换内存中的账本，退出后不保存。原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。" : "这是替换导入，不是合并。当前 Centwise 账本会先自动保存一份本地备份；原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                    Button("确认替换当前账本") { store.confirmImport() }.buttonStyle(PrimaryBarButtonStyle())
                    Button("取消") { store.pendingImport = nil }.buttonStyle(.plain)
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
                }.padding(24)
            }.background(Theme.canvas).navigationTitle("导入预览").inlineTitle()
        }.editorFrame(minHeight: 500)
    }
}

// MARK: - Dashboard

struct OverviewView: View {
    @EnvironmentObject var store: LedgerStore
    let showTransactions: () -> Void
    @State private var selected: Entry?
    init(showTransactions: @escaping () -> Void = {}) { self.showTransactions = showTransactions }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if store.period == .year { yearCard } else { spendCard }
                if !reviewEntries.isEmpty { reviewCard }
                if store.ledger.entries.isEmpty {
                    ContentUnavailableView("从今天的第一笔开始", systemImage: "pencil.line",
                                           description: Text("点右下角 + 记下收支，或在设置里导入旧账本。"))
                        .ledgerCard()
                } else {
                    recentCard
                }
                netCard
                if let budget = store.ledger.budgets.first(where: { $0.categoryID == nil }) { BudgetCard(budget: budget) }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text("数据保存在本机 · 没有云同步或广告")
                }.font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted).padding(.top, 4)
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 110)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .sheet(item: $selected) { EntryEditor(entry: $0).environmentObject(store) }
    }

    private var monthEntries: [Entry] { store.periodEntries }
    private var isDay: Bool { store.period == .day }

    // Year card: 12 monthly bars with the monthly-average line, plus yearly metrics (Copilot "Yearly metrics").
    private var yearCard: some View {
        let months = store.yearMonths
        let total = months.reduce(Int64(0)) { $0 + $1.expense }
        let incomeTotal = months.reduce(Int64(0)) { $0 + $1.income }
        let average = store.monthlyAverage(.expense)
        let averageIncome = store.monthlyAverage(.income)
        let anchor = Calendar.current.dateInterval(of: .month, for: store.month)?.start
        return VStack(spacing: 18) {
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AmountText(cents: total, size: 28, weight: .bold)
                    Text("已支出").font(.system(size: 20, weight: .semibold, design: .rounded))
                }.foregroundStyle(Theme.ink)
                HStack(spacing: 4) {
                    Text("平均每月")
                    AmountText(cents: average, size: 13, weight: .semibold)
                }.font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
                Chart {
                    ForEach(months) { item in
                        BarMark(x: .value("月份", item.month, unit: .month), y: .value("支出", Double(item.expense) / 100), width: .ratio(0.62))
                            .foregroundStyle(item.month == anchor ? Theme.brand : (item.expense > average ? Theme.over.opacity(0.75) : Theme.under.opacity(0.75)))
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("平均", Double(average) / 100))
                        .foregroundStyle(Theme.ink.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            HStack(spacing: 1) { Text("月均 "); AmountText(cents: average, size: 10, weight: .bold, sign: "") }
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 5))
                        }
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(.dateTime.month(.defaultDigits))).font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                        }.foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: 150).padding(.top, 10)
                .accessibilityLabel("近一年每月支出，虚线为月均")
                Text(store.yearRangeText + " · 红色高于月均，绿色低于月均")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity).ledgerCard(padding: 20)

            VStack(alignment: .leading, spacing: 10) {
                CardCaption(title: "年度指标", trailing: "按 \(store.averageMonthCount) 个月平均")
                VStack(spacing: 0) {
                    metricRow("近一年总支出", total)
                    Divider().overlay(Theme.track)
                    metricRow("平均每月支出", average)
                    Divider().overlay(Theme.track)
                    metricRow("近一年总收入", incomeTotal, color: Theme.income)
                    Divider().overlay(Theme.track)
                    metricRow("平均每月结余", averageIncome - average, color: averageIncome - average >= 0 ? Theme.income : Theme.over)
                }.ledgerCard(padding: 14)
            }
        }
    }

    private func metricRow(_ title: String, _ value: Int64, color: Color = Theme.ink) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink)
            Spacer()
            AmountText(cents: value, size: 16, weight: .bold).foregroundStyle(color)
        }.padding(.vertical, 11)
    }
    private var reviewEntries: [Entry] {
        store.ledger.entries.filter { $0.needsReview || $0.pending }.sorted { $0.date > $1.date }
    }

    // Spend card: total, comparison with last month, cumulative line chart.
    private var spendCard: some View {
        let chart = SpendSeries(store: store)
        let difference = chart.currentTotal - chart.previousAtSameDay
        let over = difference > 0
        return VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AmountText(cents: chart.currentTotal, size: 28, weight: .bold)
                Text("已支出").font(.system(size: 20, weight: .semibold, design: .rounded))
            }.foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                Text(isDay ? "昨天同期" : "上月同期")
                AmountText(cents: chart.previousAtSameDay, size: 13, weight: .medium)
            }.font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.accent)
            Chart {
                ForEach(chart.previous) { point in
                    LineMark(x: .value("时段", point.step), y: .value("金额", point.value), series: .value("系列", "上期"))
                        .foregroundStyle(Theme.muted.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(chart.current) { point in
                    LineMark(x: .value("时段", point.step), y: .value("金额", point.value), series: .value("系列", "本期"))
                        .foregroundStyle(over ? Theme.over : Theme.under)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = chart.current.last, chart.previousAtSameDay > 0 || chart.currentTotal > 0 {
                    PointMark(x: .value("时段", last.step), y: .value("金额", last.value))
                        .foregroundStyle(over ? Theme.over : Theme.under).symbolSize(70)
                        .annotation(position: .top, alignment: .trailing, spacing: 6) {
                            HStack(spacing: 1) {
                                AmountText(cents: abs(difference), size: 11, weight: .bold, sign: "")
                                Text(over ? " 超出" : " 少花")
                            }.font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(over ? Theme.over : Theme.under, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
            .chartXScale(domain: chart.domain)
            .frame(height: 140).padding(.top, 14)
            .accessibilityLabel(isDay ? "今天累计支出走势，虚线为昨天" : "本月累计支出走势，虚线为上月")
        }.frame(maxWidth: .infinity).ledgerCard(padding: 20)
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardCaption(title: "待核对", trailing: "\(reviewEntries.count) 笔")
            VStack(spacing: 0) {
                ForEach(Array(reviewEntries.prefix(3))) { entry in
                    Button { selected = entry } label: { EntryRow(entry: entry, showDate: true) }.buttonStyle(.plain)
                }
            }.ledgerCard(padding: 14)
            Text("红点为旧账本待核对记录，橙点为待入账；点开即可编辑。")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardCaption(title: "最近账单", trailing: "全部 \(monthEntries.count) 笔", action: showTransactions)
            VStack(spacing: 10) {
                if monthEntries.isEmpty {
                    Text(isDay ? "这一天还没有记录。" : (store.period == .year ? "近一年还没有记录。" : "这个月还没有记录。")).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(groupedByDay(Array(monthEntries.prefix(6))), id: \.day) { group in
                    VStack(spacing: 0) {
                        DayHeading(date: group.day, centered: true).padding(.bottom, 2)
                        ForEach(group.entries) { entry in
                            Button { selected = entry } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                        }
                    }
                }
            }.ledgerCard(padding: 14)
        }
    }

    private var netCard: some View {
        let income = store.periodTotal(.income)
        let expense = store.periodTotal(.expense)
        let net = income - expense
        let scale = Double(max(income, expense, 1))
        return VStack(alignment: .leading, spacing: 10) {
            CardCaption(title: store.periodWord + "结余")
            VStack(alignment: .leading, spacing: 14) {
                AmountText(cents: net, size: 26, weight: .bold)
                    .foregroundStyle(net >= 0 ? Theme.income : Theme.over)
                flowBar("收入", value: income, ratio: Double(max(income, 0)) / scale, color: Theme.income)
                flowBar("支出", value: expense, ratio: Double(max(expense, 0)) / scale, color: Theme.brand)
            }.ledgerCard(padding: 18)
        }
    }

    private func flowBar(_ label: String, value: Int64, ratio: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                Spacer()
                AmountText(cents: value, size: 14, weight: .semibold).foregroundStyle(Theme.ink)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, ratio)))
                }
            }.frame(height: 8)
        }
    }
}

/// Cumulative spend through the selected period and the one before it:
/// by hour for a day (today vs yesterday), by day for a month (this month vs last).
private struct SpendSeries {
    struct Point: Identifiable { let step: Int; let value: Double; var id: Int { step } }
    var current: [Point] = []
    var previous: [Point] = []
    var currentTotal: Int64 = 0
    var previousAtSameDay: Int64 = 0
    var domain: ClosedRange<Int> = 0...24

    @MainActor init(store: LedgerStore) {
        let calendar = Calendar.current
        let isDay = store.period == .day
        let interval = store.interval
        let previousInterval = store.previousInterval
        // Steps: hours 1...24 for a day (0 = midnight start), days 1...n for a month.
        func bucket(_ date: Date) -> Int {
            isDay ? min(24, calendar.component(.hour, from: date) + 1) : calendar.component(.day, from: date)
        }
        let first = isDay ? 0 : 1
        let count = isDay ? 24 : (calendar.range(of: .day, in: .month, for: interval.start)?.count ?? 30)
        let previousCount = isDay ? 24 : (calendar.range(of: .day, in: .month, for: previousInterval.start)?.count ?? 30)
        domain = first...max(count, first + 1)
        let now = Date.now
        let lastStep: Int
        if store.isCurrentPeriod {
            lastStep = isDay ? min(24, calendar.component(.hour, from: now) + 1) : calendar.component(.day, from: now)
        } else {
            lastStep = count
        }

        var thisSteps = [Int64](repeating: 0, count: 33)
        for entry in store.entries(in: interval) where entry.kind == .expense { thisSteps[bucket(entry.date)] += entry.amount }
        var lastSteps = [Int64](repeating: 0, count: 33)
        for entry in store.entries(in: previousInterval) where entry.kind == .expense { lastSteps[bucket(entry.date)] += entry.amount }

        var running: Int64 = 0
        if isDay { current.append(Point(step: 0, value: 0)) }
        for step in 1...max(1, lastStep) {
            running += thisSteps[step]
            current.append(Point(step: step, value: Double(running) / 100))
        }
        currentTotal = running
        running = 0
        if isDay { previous.append(Point(step: 0, value: 0)) }
        for step in 1...previousCount {
            running += lastSteps[step]
            previous.append(Point(step: step, value: Double(running) / 100))
            if step == min(lastStep, previousCount) { previousAtSameDay = running }
        }
    }
}

// MARK: - Transactions

struct TransactionsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var search = ""
    @State private var kind = "all"
    @State private var selected: Entry?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                searchCard.padding(.bottom, 18)
                HStack(alignment: .firstTextBaseline) {
                    Text(heading)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    AmountText(cents: monthTotal, size: 20, weight: .bold, sign: "")
                }.foregroundStyle(Theme.ink).padding(.bottom, 2)
                Text(kind == "all" ? "\(filtered.count) 笔 · 合计为\(store.period == .day ? "当天" : store.periodWord)支出" : "\(filtered.count) 笔 · 合计为所选类型")
                    .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted).padding(.bottom, 12)
                if filtered.isEmpty {
                    Text(search.isEmpty ? (store.period == .day ? "这一天没有符合条件的账单" : (store.period == .year ? "近一年没有符合条件的账单" : "这个月没有符合条件的账单")) : "没有找到“\(search)”")
                        .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                ForEach(groupedByDay(filtered), id: \.day) { group in
                    DayHeading(date: group.day).padding(.top, 12).padding(.bottom, 2)
                    ForEach(group.entries) { entry in
                        Button { selected = entry } label: { EntryRow(entry: entry) }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 110)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet(item: $selected) { EntryEditor(entry: $0).environmentObject(store) }
    }

    private var searchCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("搜索备注、分类、账户、交易对象", text: $search)
                .textFieldStyle(.plain).font(.system(size: 16, design: .rounded))
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
            Menu {
                Picker("类型", selection: $kind) {
                    Text("全部").tag("all")
                    ForEach([EntryKind.expense, .income, .transfer, .adjustment]) { Text($0.title).tag($0.rawValue) }
                }
            } label: {
                Image(systemName: kind == "all" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(kind == "all" ? Theme.muted : Theme.accent)
                    .frame(width: 30, height: 30)
            }.menuIndicator(.hidden).accessibilityLabel("按类型筛选")
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke, lineWidth: 0.75) }
    }

    private var heading: String {
        switch store.period {
        case .day: store.month.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide))
        case .month: store.month.formatted(.dateTime.year().month(.wide))
        case .year: store.periodName
        }
    }

    private var monthTotal: Int64 {
        if kind == "all" { return filtered.filter { $0.kind == .expense && !$0.pending }.reduce(0) { $0 + $1.amount } }
        return filtered.filter { !$0.pending }.reduce(0) { $0 + $1.amount }
    }

    private var filtered: [Entry] {
        let interval = store.interval
        return store.ledger.entries.filter { entry in
            entry.date >= interval.start && entry.date < interval.end && (kind == "all" || entry.kind.rawValue == kind)
            && (search.isEmpty || "\(entry.note) \(entry.payee) \(store.categoryName(entry)) \(store.accountName(entry.accountID))".localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
    }
}

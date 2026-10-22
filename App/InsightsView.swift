import SwiftUI
import Charts
#if SWIFT_PACKAGE
import LedgerCore
#endif

/// Copilot "Categories" page: donut summary, spent-vs-budget rows, six-month trend.
struct InsightsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var target: BudgetTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                categoriesSection
                if let total = totalBudget { BudgetCard(budget: total).onTapGesture { target = BudgetTarget(budget: total) } }
                trendSection
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 110)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .sheet(item: $target) { BudgetEditor(budget: $0.budget, categoryID: $0.categoryID).environmentObject(store) }
    }

    private var spending: [(category: LedgerCategory, amount: Int64)] { store.periodCategorySpending }
    private var expenseTotal: Int64 { store.periodTotal(.expense) }
    private var isDay: Bool { store.period == .day }
    private var totalBudget: Budget? { store.ledger.budgets.first { $0.categoryID == nil } }
    private var budgetLimit: Int64? {
        if let totalBudget { return totalBudget.limit }
        let sum = store.ledger.budgets.reduce(Int64(0)) { $0 + $1.limit }
        return sum > 0 ? sum : nil
    }

    // MARK: Summary

    private var summaryCard: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                AmountText(cents: expenseTotal, size: 22, weight: .bold).foregroundStyle(Theme.ink)
                Text(store.periodWord + "支出").font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            donut.frame(width: 92, height: 92)
            VStack(alignment: .trailing, spacing: 4) {
                if let budgetLimit {
                    AmountText(cents: budgetLimit, size: 22, weight: .bold).foregroundStyle(Theme.ink)
                    Text(totalBudget == nil ? "分类预算合计" : "总预算").font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                } else {
                    Button { target = BudgetTarget(budget: nil) } label: {
                        Text("设预算").font(.system(size: 15, weight: .bold, design: .rounded))
                    }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    Text("还没有预算").font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.ledgerCard(padding: 20)
    }

    @ViewBuilder private var donut: some View {
        let slices = spending.filter { $0.amount > 0 }
        if slices.isEmpty {
            Circle().stroke(Theme.track, lineWidth: 14).padding(7)
        } else {
            Chart(slices, id: \.category.id) { row in
                SectorMark(angle: .value("金额", Double(row.amount)), innerRadius: .ratio(0.7), angularInset: 1.2)
                    .foregroundStyle(Theme.tint(for: row.category.id)).cornerRadius(2)
            }.chartLegend(.hidden)
                .accessibilityLabel(store.periodWord + "支出分类占比")
        }
    }

    // MARK: Spent vs budget rows

    private struct Row: Identifiable {
        let category: LedgerCategory
        let spent: Int64
        let budget: Budget?
        /// Budgets are monthly, so the bar always shows progress for the whole month.
        let monthSpent: Int64
        var id: String { category.id }
    }

    private var rows: [Row] {
        let spentByID = Dictionary(spending.map { ($0.category.id, $0.amount) }, uniquingKeysWith: +)
        let budgetByID = Dictionary(store.ledger.budgets.compactMap { budget in budget.categoryID.map { ($0, budget) } },
                                    uniquingKeysWith: { first, _ in first })
        return store.ledger.categories.filter { $0.kind == .expense }
            .compactMap { category -> Row? in
                let spent = spentByID[category.id] ?? 0
                let budget = budgetByID[category.id]
                guard spent != 0 || budget != nil else { return nil }
                let monthSpent = budget.map { store.ledger.spent($0, month: store.month) } ?? 0
                return Row(category: category, spent: spent, budget: budget, monthSpent: monthSpent)
            }
            .sorted { $0.spent == $1.spent ? $0.category.name < $1.category.name : $0.spent > $1.spent }
    }

    private var categoriesSection: some View {
        let list = rows
        let hidden = store.ledger.categories.filter { $0.kind == .expense }.count - list.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardCaption(title: "分类")
                Spacer()
                Text(isDay ? "今日" : (store.period == .year ? "近一年" : "已支出")).frame(width: 76, alignment: .trailing)
                Spacer().frame(width: 74)
                Text("月预算").frame(width: 62, alignment: .trailing)
            }.font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Theme.muted)
            VStack(spacing: 0) {
                if list.isEmpty {
                    Text(isDay ? "这一天还没有支出" : (store.period == .year ? "近一年还没有支出" : "本月还没有支出")).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                }
                ForEach(list) { row in
                    Button { target = BudgetTarget(budget: row.budget, categoryID: row.category.id) } label: { rowView(row) }
                        .buttonStyle(.plain)
                }
            }.ledgerCard(padding: 14)
            HStack {
                Text(store.period == .month ? (hidden > 0 ? "另有 \(hidden) 个分类本月没有支出" : "点分类可设置或修改它的月预算") : "进度条为本月预算使用情况")
                Spacer()
                Button { target = BudgetTarget(budget: nil) } label: { Label("新预算", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 13, weight: .semibold, design: .rounded))
            }.font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }

    private func rowView(_ row: Row) -> some View {
        let tint = Theme.tint(for: row.category.id)
        let ratio = row.budget.map { Double(row.monthSpent) / Double(max($0.limit, 1)) } ?? 0
        return HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Image(systemName: row.category.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 18)
            Text(row.category.name).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            AmountText(cents: row.spent, size: 14, weight: .semibold).foregroundStyle(Theme.ink)
                .frame(width: 76, alignment: .trailing)
            Group {
                if row.budget != nil { BudgetBar(ratio: ratio) } else { Capsule().fill(Theme.track).frame(height: 7) }
            }.frame(width: 66)
            Group {
                if let budget = row.budget {
                    AmountText(cents: budget.limit, size: 13, weight: .medium)
                } else {
                    Text("—").font(.system(size: 13, design: .rounded))
                }
            }.foregroundStyle(Theme.muted).frame(width: 62, alignment: .trailing)
        }.padding(.vertical, 9).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }

    // MARK: Trend

    private struct TrendRow: Identifiable { var id: String; var month: String; var kind: String; var amount: Int64 }
    private var trend: [TrendRow] {
        (-5...0).flatMap { offset -> [TrendRow] in
            let month = Calendar.current.date(byAdding: .month, value: offset, to: store.month) ?? store.month
            let title = month.formatted(.dateTime.month(.defaultDigits))
            return [TrendRow(id: "\(offset)-in", month: title, kind: "收入", amount: store.ledger.total(.income, month: month)),
                    TrendRow(id: "\(offset)-out", month: title, kind: "支出", amount: store.ledger.total(.expense, month: month))]
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardCaption(title: "近六个月", trailing: "已入账 · 人民币")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    legend("收入", Theme.income)
                    legend("支出", Theme.brand)
                }
                Chart(trend) { row in
                    BarMark(x: .value("月份", row.month), y: .value("金额", Double(row.amount) / 100), width: .ratio(0.32))
                        .foregroundStyle(by: .value("类型", row.kind))
                        .position(by: .value("类型", row.kind)).cornerRadius(4)
                }
                .chartForegroundStyleScale(["收入": Theme.income, "支出": Theme.brand])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(Theme.track)
                        AxisValueLabel().foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: 170)
            }.ledgerCard(padding: 18)
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
        }
    }
}

/// What the budget sheet should open on: an existing budget, or a new one (optionally for a category).
struct BudgetTarget: Identifiable {
    let budget: Budget?
    var categoryID: String? = nil
    var id: String { budget?.id ?? "new-\(categoryID ?? "all")" }
}

/// Copilot "monthly metrics" block: spent · budget · left / over.
struct BudgetCard: View {
    @EnvironmentObject var store: LedgerStore
    let budget: Budget
    var body: some View {
        let spent = store.ledger.spent(budget, month: store.month)
        let remaining = budget.limit - spent
        let ratio = Double(spent) / Double(max(budget.limit, 1))
        return VStack(alignment: .leading, spacing: 10) {
            CardCaption(title: name)
            VStack(spacing: 14) {
                HStack(alignment: .top) {
                    metric("已花", spent)
                    metric("预算", budget.limit)
                    VStack(spacing: 4) {
                        Text(remaining < 0 ? "超出" : "剩余").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1)
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 4) {
                            AmountText(cents: abs(remaining), size: 16, weight: .bold, sign: "").foregroundStyle(Theme.ink)
                            Circle().fill(remaining < 0 ? Theme.over : Theme.under).frame(width: 6, height: 6)
                        }
                    }.frame(maxWidth: .infinity)
                }
                BudgetBar(ratio: ratio, height: 8)
            }.ledgerCard(padding: 18)
        }.contentShape(Rectangle())
    }
    private func metric(_ title: String, _ value: Int64) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Theme.muted)
            AmountText(cents: value, size: 16, weight: .bold).foregroundStyle(Theme.ink)
        }.frame(maxWidth: .infinity)
    }
    private var name: String {
        guard let id = budget.categoryID else { return "月度总预算" }
        return (store.ledger.categories.first { $0.id == id }?.name ?? "分类") + "预算"
    }
}

struct BudgetEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let original: Budget?
    @State private var categoryID: String
    @State private var amount: String
    @State private var localError: String?
    @State private var showDelete = false
    init(budget: Budget? = nil, categoryID: String? = nil) {
        original = budget
        _categoryID = State(initialValue: budget?.categoryID ?? categoryID ?? "")
        _amount = State(initialValue: budget.map { Money.input($0.limit) } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("每月重复的预算") {
                    Picker("范围", selection: $categoryID) {
                        Text("全部支出").tag("")
                        ForEach(store.ledger.categories.filter { $0.kind == .expense }) { Text($0.name).tag($0.id) }
                    }
                    TextField("预算金额", text: $amount.moneyInput).moneyKeyboard()
                    Text("同一分类只能设置一个预算。总预算与分类预算各自独立，不相加。父分类预算仅包含该分类的直接分摊，不自动汇总子分类。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if original != nil { Button("删除预算", role: .destructive) { showDelete = true } }
            }.ledgerFormBackground().navigationTitle(original == nil ? "新预算" : "编辑预算").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                }
        }.editorFrame(minHeight: 360)
            .alert("请检查输入", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("知道了", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
            .confirmationDialog("删除这项预算？不会删除账单。", isPresented: $showDelete, titleVisibility: .visible) {
                Button("删除预算", role: .destructive) {
                    if store.commit({ $0.budgets.removeAll { $0.id == original?.id } }) { dismiss() }
                }
            }
    }
    private func save() {
        do {
            let budget = Budget(id: original?.id ?? UUID().uuidString, categoryID: categoryID.isEmpty ? nil : categoryID, limit: try Money.parse(amount))
            var next = store.ledger
            next.budgets.removeAll { $0.id == budget.id }; next.budgets.append(budget)
            try next.validate()
            if store.commit({ $0 = next }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

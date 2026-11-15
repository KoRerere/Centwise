import SwiftUI

private func subscriptionDayLabel(_ day: Date) -> String {
    let difference = Cal.daysBetween(Date(), day)
    if difference == 0 { return tr("今天") }
    if difference == 1 { return tr("明天") }
    if difference == -1 { return tr("昨天") }
    return Cal.year(day) == Cal.year(Date()) ? fmtMonthDay(day) : fmtYMD(day)
}

/// The 确认扣费 alert: 记一笔支出 / 跳过本期 / 取消.
struct ChargeConfirmation: ViewModifier {
    @Environment(LedgerStore.self) private var store
    @Binding var subscription: Subscription?
    var onDone: (() -> Void)?

    func body(content: Content) -> some View {
        content.cwAlert(Binding(get: {
            guard let s = subscription else { return nil }
            return CwAlert(id: "charge|\(s.id)", title: tr("确认 {name} 的扣费？", ["name": s.name]),
                           message: tr("将记一笔 {amount} 的支出（{category}），日期为 {date}。同一期只会记一次。", [
                               "amount": Money.text(s.amount), "category": store.category(s.categoryID)?.name ?? tr("其他"), "date": fmtMonthDay(s.nextDate),
                           ]),
                           actions: [
                               CwAlertAction(label: tr("记一笔支出"), prominent: true, action: {
                                   Haptics.selection(); store.confirmSubscriptionCharge(s.id); onDone?()
                               }),
                               CwAlertAction(label: tr("跳过本期"), action: { store.skipSubscriptionCharge(s.id); onDone?() }),
                               CwAlertAction(label: tr("取消")),
                           ])
        }, set: { if $0 == nil { subscription = nil } }))
    }
}

struct SubscriptionRequest: Identifiable {
    let id = newID()
    var subscription: Subscription?
}

/// 订阅: monthly fixed costs, running and cancelled subscriptions, charges waiting for confirmation.
struct SubscriptionsPage: View {
    @Environment(LedgerStore.self) private var store
    @Binding var editing: SubscriptionRequest?
    @State private var showCancelled = false
    @State private var confirming: Subscription?

    var body: some View {
        let ledger = store.ledger
        let active = ledger.activeSubscriptions.sorted { $0.nextDate != $1.nextDate ? $0.nextDate < $1.nextDate : $0.name < $1.name }
        let cancelled = ledger.subscriptions.filter(\.cancelled).sorted { ($0.cancelledAt ?? .distantPast) > ($1.cancelledAt ?? .distantPast) }
        let list = showCancelled ? cancelled : active
        let now = Date()
        PageList {
            SummaryCard(count: active.count, monthlyAverage: ledger.subscriptionMonthlyAverage,
                        thisMonth: ledger.subscriptionCharges(in: now), due: active.filter { $0.isDue(now) }.count)
            VStack(spacing: 14) {
                CapsuleSegments(values: [false, true], selected: showCancelled,
                                label: { $0 ? tr("已取消 {n}", ["n": cancelled.count]) : tr("订阅中 {n}", ["n": active.count]) }) { showCancelled = $0 }
                if list.isEmpty {
                    CwCard(padding: .hv(0, 8)) {
                        EmptyState(icon: "refresh-cw", title: showCancelled ? tr("没有已取消的订阅") : tr("还没有订阅"),
                                   message: showCancelled ? tr("取消的订阅会留在这里，历史账单不受影响。") : tr("那些每月悄悄溜走的钱，都请到这儿排排坐。"),
                                   actionLabel: showCancelled ? nil : tr("添加固定扣费项"),
                                   onAction: showCancelled ? nil : { editing = SubscriptionRequest() })
                    }
                } else {
                    CwCard(h: 16, v: 4) {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                                if i > 0 { RowDivider() }
                                SubscriptionRow(subscription: s, onOpen: { editing = SubscriptionRequest(subscription: s) }, onConfirm: { confirming = s })
                            }
                        }
                    }
                }
            }
        }
        .modifier(ChargeConfirmation(subscription: $confirming))
    }
}

private struct SummaryCard: View {
    let count: Int
    let monthlyAverage: Int
    let thisMonth: Int
    let due: Int

    var body: some View {
        CwCard(padding: .lrtb(20, 18, 20, 18)) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("月均固定费用")).cw(IOSText.footnote, color: .cwMuted)
                AmountText(cents: monthlyAverage, size: 34, weight: .bold).padding(.top, 4)
                HStack(alignment: .top) {
                    stat(tr("订阅中")) { Text(tr("{n} 个", ["n": count])).cw(20, .bold, brand: true) }
                    stat(tr("本月预计扣费")) { AmountText(cents: thisMonth, size: 20, weight: .bold) }
                }
                .padding(.top, 14)
                if due > 0 {
                    Text(tr("{n} 笔扣费待确认，确认后才会记入支出。", ["n": due])).cw(IOSText.footnote, color: .cwWarning).padding(.top, 12)
                }
            }
        }
    }

    private func stat<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).cw(IOSText.footnote, color: .cwMuted).lineLimit(1)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubscriptionRow: View {
    @Environment(LedgerStore.self) private var store
    let subscription: Subscription
    let onOpen: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        let s = subscription
        let category = store.category(s.categoryID)
        let due = s.isDue(Date())
        let detail: String = {
            if s.cancelled {
                return s.cancelledAt.map { "\(s.cycle.title) · \(tr("{date}取消", ["date": subscriptionDayLabel($0)]))" } ?? "\(s.cycle.title) · \(tr("已取消"))"
            }
            if due { return tr("待确认 · {date}应扣", ["date": subscriptionDayLabel(s.nextDate)]) }
            return "\(s.cycle.title) · \(tr("{date}扣费", ["date": subscriptionDayLabel(s.nextDate)]))"
        }()
        Pressable(onTap: onOpen) {
            HStack(spacing: 12) {
                BillIcon {
                    if let category { CategoryIcon(category, size: 24) } else { LIcon("refresh-cw", size: 19, color: .cwMuted) }
                }
                .opacity(s.cancelled ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).cw(IOSText.body, color: s.cancelled ? .cwMuted : .cwInk).lineLimit(1)
                    Text(detail).cw(14, due ? .semibold : .regular, color: due ? .cwWarning : .cwMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    AmountText(cents: s.amount, size: IOSText.body, weight: .semibold, color: s.cancelled ? .cwMuted : .cwInk, brand: false).fixedSize()
                    if due {
                        Pressable(scale: 0.94, onTap: onConfirm) {
                            Text(tr("确认")).cw(13, .semibold, color: .cwOnBrand)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(Color.cwBrand))
                        }
                        .accessibilityLabel(tr("确认扣费"))
                    }
                }
            }
            .padding(.vertical, 11)
        }
    }
}

/// 新增订阅 / 编辑订阅.
struct SubscriptionEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: Subscription?

    @State private var amount: String
    @State private var name: String
    @State private var note: String
    @State private var cycle: BillingCycle
    @State private var nextDate: Date
    @State private var categoryID: String?
    @State private var keypadVisible: Bool
    @State private var initial = ""
    @State private var placed = false
    @State private var chooser: ChooserRequest?
    @State private var pickingDate = false
    @State private var confirmCancel = false
    @State private var confirming: Subscription?
    @State private var alert: CwAlert?
    @FocusState private var nameFocus: Bool
    @FocusState private var noteFocus: Bool

    init(subscription: Subscription? = nil) {
        original = subscription
        _amount = State(initialValue: subscription.map { Money.input($0.amount) } ?? "")
        _name = State(initialValue: subscription?.name ?? "")
        _note = State(initialValue: subscription?.note ?? "")
        _cycle = State(initialValue: subscription?.cycle ?? .monthly)
        _nextDate = State(initialValue: subscription?.nextDate ?? Cal.dateOnly(Date()))
        _categoryID = State(initialValue: subscription?.categoryID)
        _keypadVisible = State(initialValue: subscription == nil)
    }

    private func snapshot() -> String { [name, amount, note, cycle.rawValue, dayKey(nextDate), categoryID ?? ""].joined(separator: "\u{1}") }
    private var cents: Int? { try? Money.parse(amount) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (cents ?? 0) > 0 }
    private var isDirty: Bool {
        // A new subscription with nothing typed closes without asking.
        if original == nil && [name, note].allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) && (cents ?? 0) == 0 { return false }
        return snapshot() != initial
    }

    private func hideKeypad() {
        nameFocus = false; noteFocus = false
        guard keypadVisible else { return }
        withAnimation(IOSMotion.smooth) { keypadVisible = false }
        if amount.contains(where: { "+−×÷".contains($0) }), let cents { amount = Money.input(cents) }
    }

    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { throw LedgerError(tr("请填写订阅名称。")) }
            let value = try Money.parse(amount)
            if value <= 0 { throw LedgerError(tr("每次扣费金额需要大于零。")) }
            let dateChanged = original == nil || dayKey(original!.nextDate) != dayKey(nextDate)
            let s = Subscription(id: original?.id ?? newID(), name: trimmed, amount: value, cycle: cycle, nextDate: nextDate, categoryID: categoryID,
                                 note: note.trimmingCharacters(in: .whitespaces), cancelled: original?.cancelled ?? false, cancelledAt: original?.cancelledAt,
                                 anchorDay: dateChanged ? Cal.day(nextDate) : original!.anchorDay, charged: original?.charged ?? [])
            if store.saveSubscription(s) { dismiss() }
        } catch {
            alert = CwAlert.info(title: tr("请检查输入"), message: (error as? LedgerError)?.message ?? "\(error)")
        }
    }

    var body: some View {
        let live = original.flatMap { o in store.ledger.subscriptions.first { $0.id == o.id } }
        SheetScaffold(title: original == nil ? tr("新增订阅") : tr("编辑订阅"), onLeading: { if isDirty { alert = .discard { dismiss() } } else { dismiss() } }, showsTitle: false, contentUnderBar: true) {
            ScrollView {
                VStack(spacing: 0) {
                    amountDisplay
                    categorySection.padding(.top, 14)
                    CwCard(h: 16, v: 0) {
                        VStack(spacing: 0) {
                            textRow("tag", $name, $nameFocus, tr("订阅名称"))
                            Rectangle().fill(Color.cwStroke).frame(height: hairline)
                            textRow("file-text", $note, $noteFocus, tr("添加备注"))
                        }
                    }
                    .padding(.top, 18)
                    if let live { actions(live).padding(.top, 18) }
                }
                .padding(.horizontal, 18).padding(.top, 34).padding(.bottom, 24)
                .contentShape(Rectangle())
                .onTapGesture { hideKeypad() }
            }
            .sheetScroll()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottom.background(BottomBarBackground()) }
            .modifier(AmountHardwareKeys(enabled: keypadVisible, text: amount, onChanged: { amount = $0 }, onSubmit: canSave ? save : nil))
        }
        .modifier(GuardedSheetDismiss {
            hideKeypad()
            if isDirty { alert = .discard { dismiss() } } else { dismiss() }
        })
        .onAppear { if !placed { placed = true; initial = snapshot() } }
        .onChange(of: nameFocus) { _, f in if f { hideKeypadOnly() } }
        .onChange(of: noteFocus) { _, f in if f { hideKeypadOnly() } }
        .cwSheet(item: $chooser, height: { req in req.parentID.map { subcategorySheetHeight(store.ledger, $0) } }) { req in
            CategoryChooser(kind: .expense, selectedID: categoryID ?? "", initialParentID: req.parentID, onPick: { categoryID = $0.isEmpty ? nil : $0 })
        }
        .cwSheet(isPresented: $pickingDate, height: 300, style: .card) {
            DateWheelSheet(initial: nextDate, minimum: Cal.date(2000, 1, 1)) { nextDate = Cal.dateOnly($0) }
        }
        .confirmationDialog("", isPresented: $confirmCancel) {
            Button(tr("标记为已取消"), role: .destructive) { if let o = original, store.cancelSubscription(o.id) { dismiss() } }
            Button(tr("取消"), role: .cancel) {}
        } message: { Text(tr("标记为已取消后不再提醒扣费，已记的历史账单会保留。")) }
        .modifier(ChargeConfirmation(subscription: $confirming, onDone: {
            if let o = original, let now = store.ledger.subscriptions.first(where: { $0.id == o.id }), !now.isDue(Date()) { dismiss() }
        }))
        .cwAlert($alert)
    }

    private func hideKeypadOnly() {
        guard keypadVisible else { return }
        withAnimation(IOSMotion.smooth) { keypadVisible = false }
        if amount.contains(where: { "+−×÷".contains($0) }), let cents { amount = Money.input(cents) }
    }

    private var amountDisplay: some View {
        let large = amount.count <= 9
        let monthly: String? = switch cycle {
        case .monthly: nil
        case .quarterly: (cents ?? 0) > 0 ? tr("约每月 {amount}", ["amount": Money.text(Int((Double(cents!) / 3).rounded()))]) : nil
        case .yearly: (cents ?? 0) > 0 ? tr("约每月 {amount}", ["amount": Money.text(Int((Double(cents!) / 12).rounded()))]) : nil
        }
        return VStack(spacing: 2) {
            Text(tr("每次扣费")).cw(IOSText.footnote, color: .cwMuted)
            Pressable(onTap: { nameFocus = false; noteFocus = false; withAnimation(IOSMotion.smooth) { keypadVisible = true } }) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Money.symbol).font(.cw(24, .bold, brand: true)).foregroundStyle(Color.cwInk)
                    Text(amount.isEmpty ? "0" : Money.groupedExpression(amount)).font(.cw(large ? 54 : 38, .bold, brand: true))
                        .foregroundStyle(amount.isEmpty ? Color.cwMuted.opacity(0.6) : .cwInk)
                    if keypadVisible { AmountCaret(fontSize: large ? 54 : 38, color: .cwInk).padding(.leading, 1) }
                }
                .lineLimit(1).minimumScaleFactor(0.4).frame(height: 64)
            }
            .accessibilityLabel(tr("金额 {amount}，轻点以用数字键盘输入", ["amount": amount.isEmpty ? "0" : amount]))
            if let monthly { Text(monthly).cw(IOSText.footnote, color: .cwMuted) }
        }
        .frame(maxWidth: .infinity)
    }

    private var categorySection: some View {
        let ledger = store.ledger
        let tops = ledger.categories.filter { $0.kind == .expense && ledger.isTopLevel($0) }
        return VStack(alignment: .leading, spacing: 12) {
            CardCaption(tr("分类"), trailing: tr("全部分类"), onTap: { hideKeypad(); chooser = ChooserRequest() })
            CategoryPager(categories: tops, chosen: ledger.category(categoryID), hasChildren: { !ledger.children(of: $0.id).isEmpty }) { c in
                if !ledger.children(of: c.id).isEmpty {
                    hideKeypad(); chooser = ChooserRequest(parentID: c.id)
                } else {
                    let chosen = ledger.category(categoryID)
                    let selected = chosen != nil && (chosen!.id == c.id || chosen!.parentID == c.id)
                    categoryID = selected ? nil : c.id
                }
            }
        }
    }

    private func textRow(_ icon: String, _ text: Binding<String>, _ focus: FocusState<Bool>.Binding, _ hint: String) -> some View {
        HStack(spacing: 10) {
            LIcon(icon, size: 20, color: .cwMuted)
            TextField("", text: text, prompt: Text(hint).foregroundStyle(Color.cwMuted))
                .font(.cw(IOSText.body)).foregroundStyle(Color.cwInk)
                .focused(focus)
                .padding(.vertical, 15)
        }
        .frame(minHeight: 52)
    }

    private func actions(_ live: Subscription) -> some View {
        let due = !live.cancelled && live.isDue(Date())
        func row(_ icon: String, _ label: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
            Pressable(onTap: action) {
                HStack(spacing: 8) {
                    LIcon(icon, size: 17, color: color)
                    Text(label).cw(IOSText.body, .medium, color: color)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        var notes = [live.cancelled ? tr("重新订阅后从下一个扣费日继续，取消期间的扣费不会补记。") : tr("到期后显示“待确认”，确认才会生成一笔支出；同一期只会记一次。")]
        if let last = live.charged.sorted().last, let date = try? parseDayKey(last) {
            notes.append(tr("已记账 {n} 期，最近一次 {date}。", ["n": live.charged.count, "date": subscriptionDayLabel(date)]))
        }
        return VStack(alignment: .leading, spacing: 8) {
            CwCard(h: 16, v: 0) {
                VStack(spacing: 0) {
                    if due {
                        row("check", tr("确认 {date} 的扣费", ["date": fmtMonthDay(live.nextDate)]), .cwInk) { confirming = live }
                        Rectangle().fill(Color.cwStroke).frame(height: hairline)
                    }
                    if live.cancelled {
                        row("undo-2", tr("重新订阅"), .cwInk) { if store.resumeSubscription(live.id) { dismiss() } }
                    } else {
                        row("circle-x", tr("标记为已取消"), .cwOver) { confirmCancel = true }
                    }
                }
            }
            Text(notes.joined(separator: " ")).cw(IOSText.footnote, color: .cwMuted).padding(.horizontal, 4)
        }
    }

    private var bottom: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    CapsuleSegments(values: BillingCycle.allCases, selected: cycle, label: \.title) { cycle = $0 }
                        .frame(width: 64 * 3)
                    Spacer(minLength: 0)
                    Pressable(onTap: { hideKeypad(); pickingDate = true }) {
                        HStack(spacing: 5) {
                            LIcon("calendar", size: 15, color: .cwMuted)
                            Text(tr("{date}扣费", ["date": subscriptionDayLabel(nextDate)])).cw(IOSText.subheadline, .semibold)
                            LIcon("chevron-down", size: 14, color: .cwMuted)
                        }
                    }
                    .accessibilityLabel(tr("下次扣费日期 {date}，轻点修改", ["date": fmtYMD(nextDate)]))
                }
                .frame(height: 34)
                PrimaryBarButton(label: tr("保存订阅"), onTap: canSave ? save : nil)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, keypadVisible ? 10 : 14)
            if keypadVisible {
                AmountKeypad(text: amount, onChanged: { amount = $0 }).transition(.move(edge: .bottom))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

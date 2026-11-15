import SwiftUI

struct AllocationDraft: Identifiable, Equatable {
    let id = newID()
    var categoryID: String
    var amount: String
}

/// Which category a chooser sheet is picking for.
struct ChooserRequest: Identifiable {
    let id = newID()
    var draftID: String?
    var parentID: String?
}


/// 记一笔 / 编辑账单: amount on the built-in keypad, category grid, note, type and date, more options.
struct EntryEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: Entry?

    @State private var kind: EntryKind
    @State private var amount: String
    @State private var date: Date
    @State private var dateEdited = false
    @State private var accountID: String
    @State private var destinationID: String
    @State private var allocations: [AllocationDraft]
    @State private var note: String
    @State private var payee: String
    @State private var pending: Bool
    @State private var reversal: Bool
    @State private var more: Bool
    @State private var keypadVisible: Bool
    @State private var limitHint = false
    @State private var limitTask: Task<Void, Never>?
    @State private var initialSnapshot = ""
    @State private var initialDay = Date()
    @State private var placed = false

    @State private var chooser: ChooserRequest?
    @State private var pickingDate = false
    @State private var confirmDelete = false
    @State private var pendingKind: (EntryKind, Bool)?
    @State private var confirmKindSwitch = false
    @State private var alert: CwAlert?
    @FocusState private var noteFocus: Bool
    @FocusState private var payeeFocus: Bool

    init(entry: Entry? = nil) {
        original = entry
        _kind = State(initialValue: entry?.kind ?? .expense)
        _amount = State(initialValue: entry == nil ? "" : Money.input(abs(entry!.amount)))
        _date = State(initialValue: entry?.date ?? Date())
        _accountID = State(initialValue: entry?.accountID ?? "")
        _destinationID = State(initialValue: entry?.destinationID ?? "")
        _allocations = State(initialValue: (entry?.allocations ?? []).map { AllocationDraft(categoryID: $0.categoryID, amount: Money.input($0.amount)) })
        _note = State(initialValue: entry?.note ?? "")
        _payee = State(initialValue: entry?.payee ?? "")
        _pending = State(initialValue: entry?.pending ?? false)
        _reversal = State(initialValue: (entry?.amount ?? 0) < 0)
        _more = State(initialValue: entry != nil && (entry!.allocations.count > 1 || entry!.pending || entry!.amount < 0 || !entry!.payee.isEmpty || entry!.needsReview))
        _keypadVisible = State(initialValue: entry == nil)
    }

    // MARK: State helpers

    private var availableAccounts: [Account] { store.ledger.accounts.filter { !$0.archived || $0.id == original?.accountID } }
    private var signedInput: String { reversal && !amount.hasPrefix("-") ? "-\(amount)" : amount }
    private var selectedCategoryID: String { allocations.count == 1 ? allocations[0].categoryID : "" }

    private func snapshot() -> String {
        ([kind.rawValue, amount, accountID, destinationID] + allocations.map { "\($0.categoryID)=\($0.amount)" }
            + [note, payee, "\(pending)", "\(reversal)"]).joined(separator: "\u{1}")
    }

    private var isDirty: Bool {
        // A new bill with nothing typed (no amount, note or payee) closes without asking, even if a
        // category, type or date was tapped along the way.
        if original == nil {
            let typed = [amount, note, payee].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !typed || (try? Money.parse(amount)) == 0 && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        }
        return snapshot() != initialSnapshot || (dateEdited && Cal.dateOnly(date) != initialDay)
    }

    /// A new bill made on an earlier day is saved with today's time unless its date was changed.
    private var effectiveDate: Date {
        if original != nil || dateEdited || Cal.sameDay(date, Date()) { return date }
        return Date()
    }

    private var typedCents: Int? { try? Money.parse(amount) }
    private var mustBePositive: Bool { kind.isFlow && !(original != nil && original!.amount == 0) }

    private var amountError: String? {
        guard let last = amount.last else { return nil }
        if last == "." || AmountKeypad.operators.contains(String(last)) { return nil }
        do { _ = try Money.parse(signedInput) } catch { return (error as? LedgerError)?.message ?? "\(error)" }
        if mustBePositive && (typedCents ?? 1) <= 0 { return tr("金额需要大于 0") }
        return nil
    }

    private var canSave: Bool {
        guard let cents = try? Money.parse(signedInput) else { return false }
        if !accountID.isEmpty && !availableAccounts.contains(where: { $0.id == accountID }) { return false }
        if kind == .transfer { return cents > 0 && !destinationID.isEmpty && destinationID != accountID }
        if kind == .adjustment { return true }
        if mustBePositive { return !amount.isEmpty }
        if cents == 0 && original?.amount != 0 { return false }
        if allocations.count == 1 { return true }
        return !allocations.isEmpty && allocations.allSatisfy { !$0.categoryID.isEmpty }
    }

    private func setAmount(_ value: String) {
        amount = value
        if allocations.count == 1 { allocations[0].amount = signedInput }
    }

    private func collapseExpression() {
        guard amount.contains(where: { "+−×÷/".contains($0) }), let cents = try? Money.parse(signedInput) else { return }
        setAmount(Money.input(reversal ? -cents : cents).replacingOccurrences(of: "-", with: ""))
    }

    private func hideKeypad() {
        noteFocus = false; payeeFocus = false
        if keypadVisible {
            withAnimation(IOSMotion.smooth) { keypadVisible = false }
            collapseExpression()
        }
    }

    private func onLimit() {
        limitTask?.cancel()
        withAnimation(IOSMotion.snappy) { limitHint = true }
        limitTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { withAnimation(IOSMotion.snappy) { limitHint = false } }
        }
    }

    private func selectKind(_ next: EntryKind, refund: Bool) {
        if next == kind {
            if reversal != refund { reversal = refund; if allocations.count == 1 { allocations[0].amount = signedInput } }
            return
        }
        if allocations.count > 1 {
            pendingKind = (next, refund)
            confirmKindSwitch = true
            return
        }
        applyKind(next, refund: refund)
    }

    private func applyKind(_ next: EntryKind, refund: Bool) {
        kind = next
        reversal = false
        allocations = next.isFlow ? [AllocationDraft(categoryID: "", amount: amount)] : []
        noteFocus = false; payeeFocus = false
        withAnimation(IOSMotion.smooth) { keypadVisible = true }
        if refund { reversal = true; if allocations.count == 1 { allocations[0].amount = signedInput } }
    }

    private func selectCategory(_ id: String, draftID: String? = nil) {
        if let draftID, let i = allocations.firstIndex(where: { $0.id == draftID }) {
            allocations[i].categoryID = id
        } else if allocations.count <= 1 {
            allocations = [AllocationDraft(categoryID: id, amount: signedInput)]
        }
    }

    private func topOf(_ id: String) -> LedgerCategory? {
        guard let c = store.ledger.category(id) else { return nil }
        return store.ledger.category(c.parentID) ?? c
    }

    /// Top-level categories of this kind, the 10 most used first, the rest in ledger order.
    private func quickCategories() -> [LedgerCategory] {
        var usage: [String: Int] = [:]
        for e in store.ledger.entries where e.kind == kind {
            for a in e.allocations { usage[topOf(a.categoryID)?.id ?? a.categoryID, default: 0] += 1 }
        }
        let categories = store.ledger.categories.filter { $0.kind == kind && topOf($0.id)?.id == $0.id }
        let indexed = categories.enumerated().sorted { a, b in
            let l = usage[a.element.id] ?? 0, r = usage[b.element.id] ?? 0
            return l == r ? a.offset < b.offset : l > r
        }
        var result = Array(indexed.prefix(10).map(\.element))
        result += categories.filter { c in !result.contains { $0.id == c.id } }
        return result
    }

    // MARK: Actions

    private func save() {
        if mustBePositive && (typedCents ?? 1) <= 0 {
            withAnimation(IOSMotion.smooth) { keypadVisible = true }
            alert = CwAlert.info(title: tr("金额需要大于 0"), message: tr("{kind}金额不能是负数或零，请继续编辑。要记退款，请切换到“退款”。", ["kind": kind.title]))
            return
        }
        do {
            let cents = try Money.parse(signedInput)
            var account = accountID
            if account.isEmpty {
                guard let id = store.defaultAccountID() else { return }
                account = id
                accountID = id
            }
            if kind == .transfer && cents <= 0 { throw LedgerError(tr("转账金额必须大于零。")) }
            if kind.isFlow && cents == 0 && original?.amount != 0 { throw LedgerError(tr("收支金额不能为零。")) }
            var drafts = allocations
            if kind.isFlow && drafts.count == 1 && drafts[0].categoryID.isEmpty {
                var other = store.otherCategory(kind)
                if other == nil {
                    let created = LedgerCategory(name: kind == .income ? tr("其他收入") : tr("其他"), kind: kind, symbol: "ellipsis")
                    guard store.commit({ $0.categories.append(created) }) else { return }
                    other = created
                }
                drafts[0].categoryID = other!.id
            }
            let split: [Allocation] = kind.isFlow ? try drafts.map { d in
                Allocation(categoryID: d.categoryID, amount: drafts.count == 1 ? cents
                           : try Money.parse(d.amount.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".")))
            } : []
            let entry = Entry(id: original?.id ?? newID(), kind: kind, amount: cents, date: effectiveDate, accountID: account,
                              destinationID: kind == .transfer ? destinationID : nil, allocations: split, note: note, payee: payee,
                              pending: pending, legacyType: original?.legacyType, needsReview: original?.needsReview ?? false)
            var test = store.ledger
            test.entries.removeAll { $0.id == entry.id }
            test.entries.append(entry)
            try test.validate()
            if store.save(entry) { dismiss() }
        } catch {
            alert = CwAlert.info(title: tr("请检查输入"), message: (error as? LedgerError)?.message ?? "\(error)")
        }
    }

    private func close() {
        if isDirty { alert = .discard { dismiss() } } else { dismiss() }
    }

    // MARK: Body

    var body: some View {
        SheetScaffold(title: original == nil ? tr("记一笔") : tr("编辑账单"), onLeading: close, showsTitle: false, contentUnderBar: true) {
            ScrollView {
                VStack(spacing: 0) {
                    amountDisplay
                    if kind.isFlow { categorySection.padding(.top, 14) }
                    noteCard.padding(.top, 18)
                    advanced.padding(.top, 18)
                    if original != nil {
                        CwCard(h: 16, v: 0) {
                            Pressable(onTap: { confirmDelete = true }) {
                                HStack(spacing: 8) {
                                    LIcon("trash", size: 17, color: .cwOver)
                                    Text(tr("删除这笔记录")).cw(IOSText.body, .medium, color: .cwOver)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                            }
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 34)
                .padding(.bottom, 24)
                .contentShape(Rectangle())
                .onTapGesture { hideKeypad() }
            }
            .sheetScroll()
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottom.background(BottomBarBackground()) }
            .modifier(AmountHardwareKeys(enabled: keypadVisible, text: amount, onChanged: setAmount, onLimit: onLimit,
                                         onSubmit: canSave && !store.loadingFailed ? save : nil))
        }
        .modifier(GuardedSheetDismiss {
            hideKeypad()
            if isDirty { alert = .discard { dismiss() } } else { dismiss() }
        })
        .onAppear(perform: setUp)
        .onChange(of: noteFocus) { _, f in if f && keypadVisible { withAnimation(IOSMotion.smooth) { keypadVisible = false }; collapseExpression() } }
        .onChange(of: payeeFocus) { _, f in if f && keypadVisible { withAnimation(IOSMotion.smooth) { keypadVisible = false }; collapseExpression() } }
        .cwSheet(item: $chooser, height: { req in req.parentID.map { subcategorySheetHeight(store.ledger, $0) } }) { req in
            CategoryChooser(kind: kind, selectedID: req.draftID.flatMap { id in allocations.first { $0.id == id }?.categoryID } ?? selectedCategoryID,
                            initialParentID: req.parentID, onPick: { selectCategory($0, draftID: req.draftID) })
        }
        .cwSheet(isPresented: $pickingDate, height: 300, style: .card) {
            DateWheelSheet(initial: effectiveDate) { picked in
                let p = Cal.parts(picked), t = Cal.parts(effectiveDate)
                let value = Cal.date(p.year, p.month, p.day, t.hour, t.minute, t.second)
                if !Cal.sameDay(value, effectiveDate) { dateEdited = true }
                date = value
            }
        }
        .confirmationDialog("", isPresented: $confirmDelete) {
            Button(tr("删除记录"), role: .destructive) { if let original, store.deleteEntry(original) { dismiss() } }
            Button(tr("取消"), role: .cancel) {}
        } message: { Text(tr("删除这笔记录？删除后可在几秒内撤销。")) }
        .confirmationDialog("", isPresented: $confirmKindSwitch) {
            Button(tr("确认切换并重设分摊"), role: .destructive) { if case let (k, r)? = pendingKind { applyKind(k, refund: r) } }
            Button(tr("取消"), role: .cancel) {}
        } message: { Text(tr("切换类型会重设当前分类分摊。金额和备注会保留。")) }
        .cwAlert($alert)
    }

    private func setUp() {
        guard !placed else { return }
        placed = true
        if accountID.isEmpty { accountID = availableAccounts.first?.id ?? "" }
        if allocations.isEmpty && kind.isFlow { allocations = [AllocationDraft(categoryID: "", amount: signedInput)] }
        initialSnapshot = snapshot()
        initialDay = Cal.dateOnly(date)
    }

    // MARK: Pieces

    private var amountDisplay: some View {
        let tint: Color = reversal ? .cwIncome : (kind == .income ? .cwIncome : (kind == .transfer ? .cwAccent : .cwInk))
        let large = amount.count <= 9
        let label = reversal ? (kind == .adjustment ? tr("减少余额") : tr("退款 / 冲销金额")) : tr("{kind}金额", ["kind": kind.title])
        return VStack(spacing: 2) {
            Text(label).cw(IOSText.footnote, color: .cwMuted)
            Pressable(onTap: {
                noteFocus = false; payeeFocus = false
                withAnimation(IOSMotion.smooth) { keypadVisible = true }
            }) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(reversal ? "−\(Money.symbol)" : Money.symbol).font(.cw(24, .bold, brand: true)).foregroundStyle(tint)
                    Text(amount.isEmpty ? "0" : Money.groupedExpression(amount))
                        .font(.cw(large ? 54 : 38, .bold, brand: true))
                        .foregroundStyle(amount.isEmpty ? Color.cwMuted.opacity(0.6) : tint)
                    if keypadVisible { AmountCaret(fontSize: large ? 54 : 38, color: tint).padding(.leading, 1) }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(height: 64)
            }
            .accessibilityLabel(tr("金额 {amount}，轻点以用数字键盘输入", ["amount": amount.isEmpty ? "0" : amount]))
            if let amountError { Text(amountError).cw(IOSText.footnote, color: .cwOver).multilineTextAlignment(.center) }
            if limitHint {
                Text(tr("最多 10 位整数、2 位小数")).cw(IOSText.footnote, color: .cwWarning).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var categorySection: some View {
        if allocations.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                CardCaption(tr("分类"))
                Pressable(onTap: { withAnimation(IOSMotion.snappy) { more = true } }) {
                    CwCard(h: 16, v: 12) {
                        HStack(spacing: 6) {
                            LIcon("split", size: 16, color: .cwAccent)
                            Text(tr("{n} 个分类分摊 · 编辑", ["n": allocations.count])).cw(IOSText.subheadline, .semibold, color: .cwAccent)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            let chosen = selectedCategoryID.isEmpty ? nil : store.ledger.category(selectedCategoryID)
            VStack(alignment: .leading, spacing: 12) {
                CardCaption(tr("分类"), trailing: tr("全部分类"), onTap: { hideKeypad(); chooser = ChooserRequest() })
                CategoryPager(categories: quickCategories(), chosen: chosen, hasChildren: { !store.ledger.children(of: $0.id).isEmpty }) { c in
                    if !store.ledger.children(of: c.id).isEmpty {
                        hideKeypad()
                        chooser = ChooserRequest(parentID: c.id)
                    } else {
                        selectCategory(c.id)
                    }
                }
                .id(kind)
            }
        }
    }

    private var noteCard: some View {
        CwCard(h: 16, v: 0) {
            VStack(spacing: 0) {
                if kind == .transfer {
                    HStack(spacing: 10) {
                        LIcon("arrow-down-to-line", size: 17, color: .cwMuted)
                        Text(tr("转入账户")).cw(IOSText.body, .semibold)
                        Spacer()
                        Menu {
                            Picker("", selection: $destinationID) {
                                ForEach(store.ledger.accounts.filter { !$0.archived && $0.id != accountID }) { a in Text(a.name).tag(a.id) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(destinationID.isEmpty ? tr("选择转入账户") : store.accountName(destinationID)).cw(IOSText.body, color: .cwMuted).lineLimit(1)
                                LIcon("chevron-up-down", size: 14, color: .cwMuted)
                            }
                        }
                    }
                    .frame(minHeight: 48)
                    Rectangle().fill(Color.cwStroke).frame(height: hairline)
                }
                HStack(alignment: .top, spacing: 10) {
                    LIcon("file-text", size: 20, color: .cwMuted).padding(.top, 15)
                    TextField("", text: $note, prompt: Text(tr("添加备注")).foregroundStyle(Color.cwMuted), axis: .vertical)
                        .lineLimit(1...3)
                        .font(.cw(IOSText.body))
                        .foregroundStyle(Color.cwInk)
                        .focused($noteFocus)
                        .padding(.vertical, 15)
                }
                .frame(minHeight: 52)
            }
        }
    }

    private var advanced: some View {
        let reversalLabel = kind == .adjustment ? tr("减少余额") : tr("退款 / 冲销")
        return CwCard(h: 16, v: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Pressable(onTap: { withAnimation(IOSMotion.snappy) { more.toggle() } }) {
                    HStack(spacing: 2) {
                        Text(tr("更多选项")).cw(IOSText.body, .semibold)
                        Spacer()
                        if !more { Text(tr("分摊 · 交易对象 · 待入账")).cw(IOSText.footnote, color: .cwMuted) }
                        LIcon("chevron-right", size: 16, color: .cwMuted).rotationEffect(.degrees(more ? 90 : 0))
                    }
                    .frame(minHeight: 48)
                }
                if more {
                    if kind != .transfer {
                        switchRow(reversalLabel, $reversal)
                            .onChange(of: reversal) { if allocations.count == 1 { allocations[0].amount = signedInput } }
                        if reversal {
                            Text(tr("输入正数金额，保存时按负数记入原类型。多分类分摊仍需核对各项正负金额。")).cw(IOSText.footnote, color: .cwMuted).padding(.bottom, 8)
                        }
                    }
                    switchRow(tr("待入账"), $pending)
                    HStack(spacing: 10) {
                        LIcon("store", size: 17, color: .cwMuted)
                        FormTextField(text: $payee, hint: tr("交易对象（可选）"), focus: $payeeFocus)
                    }
                    if kind.isFlow { splitOptions }
                    if let legacy = original?.legacyType {
                        Text(tr("Money Pro 源类型 {type}", ["type": legacy]) + (original!.needsReview ? " · \(tr("待核对"))" : ""))
                            .cw(IOSText.footnote, color: .cwMuted).padding(.vertical, 8)
                    }
                    Spacer().frame(height: 6)
                }
            }
        }
    }

    private func switchRow(_ label: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { Text(label).cw(IOSText.body) }.frame(minHeight: 48)
    }

    private var splitStatus: some View {
        let total = try? Money.parse(signedInput)
        var sum = 0
        var problems: [String] = []
        for (i, d) in allocations.enumerated() {
            let n = i + 1
            if d.categoryID.isEmpty { problems.append(tr("第 {n} 行还没选分类", ["n": n])) }
            let text = d.amount.trimmingCharacters(in: .whitespaces)
            if let cents = try? Money.parse(text.isEmpty ? "0" : text) {
                if cents == 0 { problems.append(tr("第 {n} 行金额为 0", ["n": n])) }
                sum += cents
            } else {
                problems.append(tr("第 {n} 行金额格式不对", ["n": n]))
            }
        }
        let ids = allocations.map(\.categoryID).filter { !$0.isEmpty }
        if Set(ids).count != ids.count { problems.append(tr("有重复的分类")) }
        return VStack(alignment: .leading, spacing: 2) {
            if let total {
                let diff = total - sum
                let balance = diff == 0 ? tr("已分摊 {sum} · 与总额一致", ["sum": Money.text(sum)])
                    : diff > 0 ? tr("已分摊 {sum} · 还剩 {left}", ["sum": Money.text(sum), "left": Money.text(diff)])
                    : tr("已分摊 {sum} · 超出 {over}", ["sum": Money.text(sum), "over": Money.text(-diff)])
                Text(balance).cw(IOSText.footnote, .semibold, color: diff == 0 ? .cwUnder : .cwOver)
            }
            if let first = problems.first { Text(first).cw(IOSText.footnote, color: .cwOver) }
        }
    }

    private var splitOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if allocations.count > 1 {
                splitStatus.padding(.top, 8).padding(.bottom, 4)
                ForEach($allocations) { $draft in
                    HStack(spacing: 0) {
                        Pressable(onTap: { hideKeypad(); chooser = ChooserRequest(draftID: draft.id) }) {
                            Text(store.category(draft.categoryID)?.name ?? tr("选择分类")).cw(IOSText.body, .semibold, color: .cwAccent)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        FormTextField(text: $draft.amount, hint: tr("金额"), keyboard: .numbersAndPunctuation, alignment: .trailing)
                            .padding(.horizontal, 10)
                            .frame(width: 96)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cwCanvas))
                        Pressable(onTap: { let id = draft.id; allocations.removeAll { $0.id == id } }) {
                            LIcon("circle-x", size: 18, color: .cwOver).padding(8)
                        }
                        .accessibilityLabel(tr("移除这个分摊"))
                    }
                    .padding(.vertical, 4)
                }
            }
            Pressable(onTap: {
                if allocations.isEmpty { allocations.append(AllocationDraft(categoryID: "", amount: signedInput)) }
                allocations.append(AllocationDraft(categoryID: "", amount: "0"))
            }) {
                HStack(spacing: 6) {
                    LIcon("plus", size: 16, color: .cwAccent, strokeWidth: 2.5)
                    Text(tr("添加分摊分类")).cw(IOSText.body, .semibold, color: .cwAccent)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
    }

    private var typeDateBar: some View {
        var modes: [String] = ["expense", "income", "refund"]
        if original?.kind == .transfer { modes.append("transfer") }
        if original?.kind == .adjustment { modes.append("adjustment") }
        let current: String = switch kind {
        case .expense: reversal ? "refund" : "expense"
        case .income: "income"
        case .transfer: "transfer"
        case .adjustment: "adjustment"
        }
        func label(_ m: String) -> String {
            switch m {
            case "expense": EntryKind.expense.title
            case "income": EntryKind.income.title
            case "refund": tr("退款")
            case "transfer": EntryKind.transfer.title
            default: EntryKind.adjustment.title
            }
        }
        let d = effectiveDate
        let today = DayHeading.label(d)
        let dateLabel = today == tr("今天") || today == tr("昨天") ? today : (Cal.year(d) == Cal.year(Date()) ? fmtMonthDay(d) : fmtYMD(d))
        return HStack(spacing: 12) {
            CapsuleSegments(values: modes, selected: current, label: label) { m in
                let k: EntryKind = m == "income" ? .income : m == "transfer" ? .transfer : m == "adjustment" ? .adjustment : .expense
                selectKind(k, refund: m == "refund")
            }
            .frame(width: CGFloat(64 * modes.count))
            Spacer(minLength: 0)
            Pressable(onTap: { hideKeypad(); pickingDate = true }) {
                HStack(spacing: 5) {
                    LIcon("calendar", size: 15, color: .cwMuted)
                    Text(dateLabel).cw(IOSText.subheadline, .semibold)
                    LIcon("chevron-down", size: 14, color: .cwMuted)
                }
            }
            .accessibilityLabel(tr("日期 {date}，轻点修改", ["date": fmtYMD(d)]))
        }
        .frame(height: 34)
    }

    private var bottom: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                typeDateBar
                PrimaryBarButton(label: tr("保存这笔{kind}", ["kind": kind.title]), onTap: canSave && !store.loadingFailed ? save : nil)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, keypadVisible ? 10 : 14)
            if keypadVisible {
                AmountKeypad(text: amount, onChanged: setAmount, onLimit: onLimit)
                    .transition(.move(edge: .bottom))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

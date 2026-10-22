import SwiftUI
#if SWIFT_PACKAGE
import LedgerCore
#endif

private struct AllocationDraft: Identifiable {
    var id = UUID()
    var categoryID: String
    var amount: String
}
private enum EntryInput: Hashable { case amount, note, payee, split(UUID) }

struct EntryEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let original: Entry?
    @State private var kind: EntryKind
    @State private var amount: String
    @State private var date: Date
    @State private var accountID: String
    @State private var destinationID: String
    @State private var allocations: [AllocationDraft]
    @State private var note: String
    @State private var payee: String
    @State private var pending: Bool
    @State private var reversal: Bool
    @State private var more: Bool
    @State private var showDelete = false
    @State private var localError: String?
    @State private var showCategories = false
    @State private var splitCategoryTarget: UUID?
    @State private var proposedKind: EntryKind?
    @FocusState private var focus: EntryInput?

    init(entry: Entry? = nil) {
        original = entry
        _kind = State(initialValue: entry?.kind ?? .expense)
        _amount = State(initialValue: entry.map { Money.input(abs($0.amount)) } ?? "")
        _date = State(initialValue: entry?.date ?? .now)
        _accountID = State(initialValue: entry?.accountID ?? "")
        _destinationID = State(initialValue: entry?.destinationID ?? "")
        _allocations = State(initialValue: entry?.allocations.map { AllocationDraft(categoryID: $0.categoryID, amount: Money.input($0.amount)) } ?? [])
        _note = State(initialValue: entry?.note ?? "")
        _payee = State(initialValue: entry?.payee ?? "")
        _pending = State(initialValue: entry?.pending ?? false)
        _reversal = State(initialValue: (entry?.amount ?? 0) < 0)
        _more = State(initialValue: entry.map { $0.allocations.count > 1 || $0.pending || $0.amount < 0 || !$0.payee.isEmpty || $0.needsReview } ?? false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        typeSelector
                        amountInput
                        if kind == .income || kind == .expense { categorySection }
                        VStack(spacing: 0) {
                            accountAndDate
                            if kind == .transfer { cardDivider; destinationSelector }
                            cardDivider
                            noteInput
                        }.ledgerCard(padding: 16)
                        advancedOptions
                    }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 22)
                        .frame(maxWidth: 520).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                saveBar
            }.background(Theme.canvas)
                .navigationTitle(original == nil ? "记一笔" : "编辑账单").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(original == nil ? "记一笔" : "编辑账单")
                            .font(.system(size: 13, weight: .bold, design: .rounded)).tracking(1.2)
                            .foregroundStyle(Theme.muted)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.accessibilityIdentifier("entry.cancel")
                    }
                    #if os(iOS)
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { focus = nil }
                    }
                    #endif
                }
        }.tint(Theme.accent)
            .toggleStyle(.switch)
            #if os(macOS)
            .frame(width: 430, height: 790)
            #endif
            .onAppear { configure() }
            .onChange(of: amount) { _, value in
                if value.hasPrefix("-"), kind != .transfer {
                    reversal = true; more = true; amount = String(value.dropFirst())
                }
                synchronizeSingleAllocation()
            }
            .onChange(of: reversal) { _, _ in synchronizeSingleAllocation() }
            .onChange(of: accountID) { _, value in
                if destinationID == value { destinationID = "" }
            }
            .sheet(isPresented: $showCategories, onDismiss: { splitCategoryTarget = nil }) {
                CategoryChooser(categories: categories, selectedID: selectedCategoryID) { selectCategory($0.id) }
            }
            .alert("请检查输入", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("知道了", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
            .confirmationDialog("切换类型会重设当前分类分摊。金额和备注会保留。", isPresented: Binding(get: { proposedKind != nil }, set: { if !$0 { proposedKind = nil } }), titleVisibility: .visible) {
                Button("确认切换并重设分摊") {
                    if let next = proposedKind { applyKind(next) }; proposedKind = nil
                }
                Button("取消", role: .cancel) { proposedKind = nil }
            }
            .confirmationDialog("删除这笔记录？修改前的账本仍保留在本地快照中。", isPresented: $showDelete, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) {
                    guard let original else { return }
                    if store.commit({ $0.entries.removeAll { $0.id == original.id } }) { dismiss() }
                    else { reportSaveFailure() }
                }
                Button("取消", role: .cancel) {}
            }
    }

    private var typeSelector: some View {
        let types = EntryKind.allCases.filter { $0 != .adjustment || original?.kind == .adjustment }
        return HStack(spacing: 4) {
            ForEach(types) { type in
                let selected = kind == type
                Button { withAnimation(.easeInOut(duration: 0.18)) { kindSelection.wrappedValue = type } } label: {
                    Text(type.title).font(.system(size: 14, weight: selected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(selected ? Theme.ink : Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selected {
                                Capsule().fill(Theme.card)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("entry.kind.\(type.rawValue)")
            }
        }.padding(4).background(Theme.track.opacity(0.8), in: Capsule())
            .accessibilityElement(children: .contain).accessibilityIdentifier("entry.kind")
    }

    private var kindSelection: Binding<EntryKind> {
        Binding(get: { kind }, set: { next in
            guard next != kind else { return }
            if allocations.count > 1 { proposedKind = next } else { applyKind(next) }
        })
    }

    private var amountInput: some View {
        VStack(spacing: 6) {
            Text(reversal ? (kind == .adjustment ? "减少余额" : "退款 / 冲销金额") : "\(kind.title)金额")
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reversal ? "−¥" : "¥").font(.system(size: 24, weight: .bold, design: .rounded))
                    .baselineOffset(amount.count > 9 ? 10 : 18)
                TextField("0.00", text: $amount.moneyInput)
                    .textFieldStyle(.plain).labelsHidden().moneyKeyboard()
                    .font(.system(size: amount.count > 9 ? 36 : 52, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).monospacedDigit()
                    .frame(width: min(270, max(130, CGFloat(max(4, amount.count)) * (amount.count > 9 ? 20 : 31))))
                    .focused($focus, equals: .amount)
                    .accessibilityLabel("金额").accessibilityIdentifier("entry.amount")
            }.foregroundStyle(amountTint).frame(maxWidth: 310).padding(.vertical, 2)
            if let amountError { Text(amountError).font(.caption).foregroundStyle(Theme.over).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private var amountTint: Color {
        if reversal { return Theme.income }
        switch kind { case .income: return Theme.income; case .transfer: return Theme.accent; default: return Theme.ink }
    }

    private var openAllCategories: (() -> Void)? {
        guard allocations.count <= 1 else { return nil }
        return { splitCategoryTarget = nil; focus = nil; showCategories = true }
    }

    private var cardDivider: some View { Divider().overlay(Theme.track).padding(.vertical, 2) }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardCaption(title: "分类", trailing: allocations.count <= 1 ? "全部分类" : nil, action: openAllCategories)
                .accessibilityIdentifier("entry.categories.all")
            if allocations.count > 1 {
                Button { focus = nil; more = true } label: {
                    Label("\(allocations.count) 个分类分摊 · 编辑", systemImage: "square.split.2x2")
                        .font(.subheadline).frame(maxWidth: .infinity, minHeight: 34)
                }.buttonStyle(.bordered)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                    ForEach(quickCategories) { category in
                        let selected = selectedCategoryID == category.id
                        let tint = Theme.tint(for: category.id)
                        Button { withAnimation(.easeOut(duration: 0.15)) { selectCategory(category.id) }; focus = nil } label: {
                            VStack(spacing: 7) {
                                Image(systemName: selected ? "checkmark" : category.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selected ? Color.white : tint)
                                    .frame(width: 48, height: 48)
                                    .background(selected ? tint : tint.opacity(0.13), in: Circle())
                                Text(category.name).font(.system(size: 12, weight: selected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }.frame(maxWidth: .infinity).frame(minHeight: 76).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(category.name)
                            .accessibilityValue(selected ? "已选择" : "")
                            .accessibilityIdentifier("entry.category.\(category.id)")
                    }
                }
                if selectedCategoryID.isEmpty { Text(amount.isEmpty ? "输入金额，再选一个分类。" : "选一个分类就可以保存。").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted) }
            }
        }
    }

    private var accountAndDate: some View {
        VStack(spacing: 0) {
            LabeledContent {
                Picker(kind == .transfer ? "转出账户" : "账户", selection: $accountID) {
                    Text("选择账户").tag("")
                    ForEach(availableAccounts) { Text($0.name).tag($0.id) }
                }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("entry.account")
            } label: { rowLabel(kind == .transfer ? "转出账户" : "账户", symbol: "creditcard") }
                .frame(minHeight: 44)
            cardDivider
            HStack {
                rowLabel("日期", symbol: "calendar")
                Spacer()
                if !Calendar.current.isDateInToday(date) {
                    Button("今天") { date = .now }.buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
                }
                DatePicker("日期", selection: $date,
                           in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 4_102_444_800),
                           displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).accessibilityIdentifier("entry.date")
            }.frame(minHeight: 44)
        }
    }

    private func rowLabel(_ title: String, symbol: String) -> some View {
        Label {
            Text(title).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
        }
    }

    private var destinationSelector: some View {
        LabeledContent {
            Picker("转入账户", selection: $destinationID) {
                Text("选择转入账户").tag("")
                ForEach(store.ledger.accounts.filter { !$0.archived && $0.id != accountID }) { Text($0.name).tag($0.id) }
            }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("entry.destination")
        } label: { rowLabel("转入账户", symbol: "arrow.down.to.line") }
            .frame(minHeight: 44)
    }

    private var noteInput: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "text.alignleft").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                .frame(width: 22)
            TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(1...3)
                .textFieldStyle(.plain).font(.system(size: 15, design: .rounded))
                .focused($focus, equals: .note).accessibilityIdentifier("entry.note")
        }.padding(.vertical, 12)
    }

    private var advancedOptions: some View {
        DisclosureGroup(isExpanded: $more) {
            VStack(alignment: .leading, spacing: 16) {
                if kind != .transfer {
                    Toggle(kind == .adjustment ? "减少余额" : "退款 / 冲销", isOn: $reversal)
                    if reversal {
                        Text("输入正数金额，保存时按负数记入原类型。多分类分摊仍需核对各项正负金额。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("待入账", isOn: $pending)
                TextField("交易对象（可选）", text: $payee).textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .payee)
                if kind == .income || kind == .expense { splitOptions }
                if let type = original?.legacyType {
                    Text("Money Pro 源类型 \(type)\(original?.needsReview == true ? " · 待核对" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if original != nil { Button("删除这笔记录", role: .destructive) { showDelete = true } }
            }.font(.system(size: 15, design: .rounded)).padding(.top, 14)
        } label: {
            HStack {
                Text("更多选项").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
                if !more { Text("分摊 · 交易对象 · 待入账").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted) }
            }
        }.tint(Theme.accent).ledgerCard(padding: 16)
    }

    private var splitOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allocations.count > 1 {
                Text("分摊金额合计需等于该笔金额").font(.caption).foregroundStyle(.secondary)
                ForEach($allocations) { $draft in
                    HStack(spacing: 10) {
                        Button {
                            splitCategoryTarget = draft.id; focus = nil; showCategories = true
                        } label: {
                            Text(categories.first { $0.id == draft.categoryID }?.name ?? "选择分类").lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderless)
                        TextField("金额", text: $draft.amount.moneyInput).textFieldStyle(.roundedBorder).signedMoneyKeyboard()
                            .multilineTextAlignment(.trailing).frame(width: 90)
                            .focused($focus, equals: .split(draft.id))
                        Button(role: .destructive) { allocations.removeAll { $0.id == draft.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("移除这个分摊")
                    }.padding(.vertical, 8)
                }
            }
            Button("添加分摊分类", systemImage: "plus.circle") {
                if allocations.isEmpty { allocations = [.init(categoryID: "", amount: signedInput)] }
                allocations.append(.init(categoryID: "", amount: "0"))
            }.buttonStyle(.borderless)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if availableAccounts.isEmpty { Text("请先在账户页创建一个有效账户。").font(.caption).foregroundStyle(Theme.over) }
            Button { save() } label: { Text("保存这笔\(kind.title)") }
                .buttonStyle(PrimaryBarButtonStyle(tint: kind == .income ? Theme.income : Theme.accent))
                .disabled(!canSave || store.loadingFailed)
                .accessibilityIdentifier("entry.save")
        }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 14)
            .background(Theme.canvas)
    }

    private var categories: [LedgerCategory] { store.ledger.categories.filter { $0.kind == kind } }
    private var selectedCategoryID: String {
        if let target = splitCategoryTarget { return allocations.first { $0.id == target }?.categoryID ?? "" }
        return allocations.count == 1 ? allocations[0].categoryID : ""
    }
    private var quickCategories: [LedgerCategory] {
        var usage: [String: Int] = [:]
        for entry in store.ledger.entries where entry.kind == kind {
            for allocation in entry.allocations { usage[allocation.categoryID, default: 0] += 1 }
        }
        var result = Array(categories.enumerated().sorted {
            let lhs = usage[$0.element.id] ?? 0, rhs = usage[$1.element.id] ?? 0
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.prefix(8).map(\.element))
        if let selected = categories.first(where: { $0.id == selectedCategoryID }), !result.contains(where: { $0.id == selected.id }) {
            if result.count == 8 { result.removeLast() }; result.append(selected)
        }
        return result
    }
    private var availableAccounts: [Account] { store.ledger.accounts.filter { !$0.archived || $0.id == original?.accountID } }
    private var signedInput: String { reversal && !amount.hasPrefix("-") ? "-" + amount : amount }
    private var amountError: String? {
        guard !amount.isEmpty, !amount.hasSuffix(".") else { return nil }
        do { _ = try Money.parse(signedInput); return nil }
        catch { return error.localizedDescription }
    }
    private var canSave: Bool {
        guard let cents = try? Money.parse(signedInput), availableAccounts.contains(where: { $0.id == accountID }) else { return false }
        if kind == .transfer { return cents > 0 && !destinationID.isEmpty && destinationID != accountID }
        if kind == .adjustment { return true }
        return (cents != 0 || original?.amount == 0) && !allocations.isEmpty && allocations.allSatisfy { !$0.categoryID.isEmpty }
    }
    private func configure() {
        if accountID.isEmpty { accountID = availableAccounts.first?.id ?? "" }
        if allocations.isEmpty && [.income, .expense].contains(kind) { allocations = [.init(categoryID: "", amount: signedInput)] }
        if original == nil { focus = .amount }
    }
    private func applyKind(_ next: EntryKind) {
        kind = next; reversal = false; splitCategoryTarget = nil
        allocations = [.income, .expense].contains(next) ? [.init(categoryID: "", amount: amount)] : []
        focus = .amount
    }
    private func synchronizeSingleAllocation() {
        if allocations.count == 1 { allocations[0].amount = signedInput }
    }
    private func selectCategory(_ id: String) {
        if let target = splitCategoryTarget, let index = allocations.firstIndex(where: { $0.id == target }) { allocations[index].categoryID = id }
        else if allocations.count <= 1 { allocations = [.init(categoryID: id, amount: signedInput)] }
        splitCategoryTarget = nil
    }
    private func reportSaveFailure() { localError = store.error ?? "保存未完成，请重试。"; store.error = nil }
    private func save() {
        do {
            let cents = try Money.parse(signedInput)
            if kind == .transfer && cents <= 0 { throw LedgerError.invalid("转账金额必须大于零。") }
            if [.income, .expense].contains(kind), cents == 0, original?.amount != 0 { throw LedgerError.invalid("收支金额不能为零。") }
            let split: [Allocation] = [.income, .expense].contains(kind) ? try allocations.map {
                Allocation(categoryID: $0.categoryID, amount: allocations.count == 1 ? cents : try Money.parse($0.amount))
            } : []
            let entry = Entry(id: original?.id ?? UUID().uuidString, kind: kind, amount: cents, date: date,
                              accountID: accountID, destinationID: kind == .transfer ? destinationID : nil,
                              allocations: split, note: note, payee: payee, pending: pending,
                              legacyType: original?.legacyType, needsReview: original?.needsReview ?? false)
            var test = store.ledger
            test.entries.removeAll { $0.id == entry.id }; test.entries.append(entry)
            try test.validate()
            if store.save(entry) { dismiss() } else { reportSaveFailure() }
        } catch { localError = error.localizedDescription }
    }
}

private struct CategoryChooser: View {
    @Environment(\.dismiss) var dismiss
    let categories: [LedgerCategory]
    let selectedID: String
    let onSelect: (LedgerCategory) -> Void
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(categories.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { category in
                Button {
                    onSelect(category); dismiss()
                } label: {
                    HStack {
                        Label(category.name, systemImage: category.symbol)
                        Spacer()
                        if category.id == selectedID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.ledgerFormBackground().navigationTitle("选择分类").inlineTitle()
                .searchable(text: $search, prompt: "搜索分类")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.editorFrame(minHeight: 500)
    }
}

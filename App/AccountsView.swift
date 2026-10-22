import SwiftUI
#if SWIFT_PACKAGE
import LedgerCore
#endif

struct AccountsView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var addAccount = false
    @State private var selected: Account?
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("账面总余额").font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(Theme.muted)
                    AmountText(cents: store.ledger.accounts.reduce(0) { $0 + store.ledger.balance(of: $1.id) }, size: 32, weight: .bold)
                        .foregroundStyle(Theme.ink)
                    Text("期初余额 + 已入账记录；转账不增加总余额。").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity).ledgerCard(padding: 22)
                if store.ledger.legacy != nil {
                    Label("旧账本余额尚未对账，请核对期初余额。归档账户仍计入总余额。", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.over)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    CardCaption(title: "我的账户", trailing: "人民币 CNY")
                    VStack(spacing: 0) {
                        ForEach(store.ledger.accounts) { account in
                            Button { selected = account } label: { row(account) }.buttonStyle(.plain)
                            if account.id != store.ledger.accounts.last?.id { Divider().overlay(Theme.track).padding(.leading, 54) }
                        }
                        if store.ledger.accounts.isEmpty {
                            Text("还没有账户").font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                        }
                    }.ledgerCard(padding: 14)
                }
                Button { addAccount = true } label: { Label("添加账户", systemImage: "plus") }
                    .buttonStyle(PrimaryBarButtonStyle())
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 110)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
            .sheet(isPresented: $addAccount) { AccountEditor().environmentObject(store) }
            .sheet(item: $selected) { AccountEditor(account: $0).environmentObject(store) }
    }

    private func row(_ account: Account) -> some View {
        let tint = Theme.tint(for: account.id)
        return HStack(spacing: 12) {
            Image(systemName: account.archived ? "archivebox.fill" : "creditcard.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 40, height: 40).background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.ink)
                Text(account.archived ? "已归档 · 保留历史记录" : "本地账户").font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            AmountText(cents: store.ledger.balance(of: account.id), size: 16, weight: .semibold).foregroundStyle(Theme.ink)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted.opacity(0.6))
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}

struct AccountEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    let original: Account?
    @State private var name: String
    @State private var opening: String
    @State private var archived: Bool
    @State private var reconcile = ""
    @State private var localError: String?
    init(account: Account? = nil) {
        original = account
        _name = State(initialValue: account?.name ?? "")
        _opening = State(initialValue: Money.input(account?.openingBalance ?? 0))
        _archived = State(initialValue: account?.archived ?? false)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("账户资料") {
                    TextField("账户名称", text: $name)
                    TextField("期初余额", text: $opening.moneyInput).signedMoneyKeyboard()
                    Text("币种：人民币 CNY").foregroundStyle(.secondary)
                    Toggle("归档账户", isOn: $archived)
                }
                Section {
                    Text("期初余额是记账开始前的余额，不是当前余额。修改会影响所有时期的账面余额。归档不会删除任何记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let original {
                    Section("核对当前余额") {
                        LabeledContent("当前账面", value: Money.text(store.ledger.balance(of: original.id)))
                        TextField("实际当前余额（可为负）", text: $reconcile.moneyInput).signedMoneyKeyboard()
                        Button("生成余额调整记录") { reconcileBalance(original) }.disabled(reconcile.isEmpty)
                        Text("调整只改变账户余额，不影响收支报表。账户资料修改尚未保存时，请先保存再调整。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.ledgerFormBackground().navigationTitle(original == nil ? "新账户" : "管理账户").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                }
        }.editorFrame(minHeight: 480)
            .alert("请检查输入", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("知道了", role: .cancel) { localError = nil }
            } message: { Text(localError ?? "") }
    }
    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw LedgerError.invalid("请填写账户名称。") }
            let account = Account(id: original?.id ?? UUID().uuidString, name: trimmed, openingBalance: try Money.parse(opening), archived: archived)
            if store.commit({ ledger in
                if let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) { ledger.accounts[index] = account }
                else { ledger.accounts.append(account) }
            }) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
    private func reconcileBalance(_ account: Account) {
        do {
            guard name == account.name, opening == Money.input(account.openingBalance), archived == account.archived else {
                throw LedgerError.invalid("请先保存账户资料，再生成余额调整。")
            }
            let actual = try Money.parse(reconcile)
            let difference = actual - store.ledger.balance(of: account.id)
            guard difference != 0 else { throw LedgerError.invalid("余额已经一致，无需调整。") }
            let entry = Entry(kind: .adjustment, amount: difference, accountID: account.id, note: "余额核对调整")
            if store.save(entry) { dismiss() }
        } catch { localError = error.localizedDescription }
    }
}

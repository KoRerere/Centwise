import 'package:flutter/material.dart';

import '../../core/currency.dart';
import '../../core/models.dart';
import '../../core/money.dart';
import '../components.dart';
import '../motion.dart';
import '../icons.dart';
import '../sheets.dart';
import '../store.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import 'dashboard_page.dart' show PageList;

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  void _open(BuildContext context, [Account? account]) {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: AccountEditor(account: account)));
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    final total = ledger.accounts.fold<int>(0, (s, a) => s + ledger.balance(a.id));
    return PageList(children: [
      CwCard(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          Text(tr('账面总余额'), style: cw(IOSText.footnote, color: p.muted)),
          const SizedBox(height: 6),
          AmountText(total, size: 34, weight: FontWeight.w700, color: p.ink),
          const SizedBox(height: 6),
          Text(tr('期初余额 + 已入账记录；转账不增加总余额。'), style: cw(IOSText.footnote, color: p.muted)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardCaption(tr('我的账户'), trailing: '${currencyFor(ledger.currency).name} ${ledger.currency}'),
        const SizedBox(height: 10),
        CwCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: ledger.accounts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr('还没有账户'), textAlign: TextAlign.center, style: cw(IOSText.subheadline, color: p.muted)),
                )
              : Column(children: [
                  for (var i = 0; i < ledger.accounts.length; i++) ...[
                    if (i > 0) Padding(padding: const EdgeInsets.only(left: 52), child: Divider(height: 0.5, thickness: 0.5, color: p.cardStroke)),
                    _row(context, ledger.accounts[i]),
                  ]
                ]),
        ),
      ]),
      PrimaryBarButton(label: tr('添加账户'), icon: 'plus', onTap: () => _open(context)),
    ]);
  }

  Widget _row(BuildContext context, Account account) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final tint = categoryTint(account.id);
    return Pressable(
      onTap: () => _open(context, account),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint.withValues(alpha: 0.13), shape: BoxShape.circle),
            child: Center(child: LIcon(account.archived ? 'archive' : 'credit-card', size: 18, color: tint)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(account.name, style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(account.archived ? tr('已归档 · 保留历史记录') : tr('本地账户'), style: cw(IOSText.footnote, color: p.muted)),
            ]),
          ),
          AmountText(store.ledger.balance(account.id), size: IOSText.body, weight: FontWeight.w500, color: p.ink),
          const SizedBox(width: 4),
          LIcon('chevron-right', size: 16, color: p.muted.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.account, this.reconcile = false});
  final Account? account;

  /// Opened from "去核对": scroll to 核对当前余额.
  final bool reconcile;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.account?.name ?? '');
  late final TextEditingController _opening = TextEditingController(text: Money.input(widget.account?.openingBalance ?? 0));
  late final TextEditingController _reconcile = TextEditingController();
  late bool _archived = widget.account?.archived ?? false;
  final GlobalKey _reconcileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.reconcile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _reconcileKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(target, alignment: 0.3, duration: IOSMotion.smoothCurve.duration, curve: IOSMotion.smoothCurve);
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _reconcile.dispose();
    super.dispose();
  }

  String _normalized(String text) => text.replaceAll('。', '.').replaceAll('．', '.');

  void _save() {
    final store = StoreScope.read(context);
    try {
      final trimmed = _name.text.trim();
      if (trimmed.isEmpty) throw LedgerError(tr('请填写账户名称。'));
      final account = Account(
        id: widget.account?.id,
        name: trimmed,
        openingBalance: Money.parse(_normalized(_opening.text)),
        currency: store.ledger.currency,
        archived: _archived,
      );
      final ok = store.commit((ledger) {
        final index = ledger.accounts.indexWhere((a) => a.id == account.id);
        if (index >= 0) {
          ledger.accounts[index] = account;
        } else {
          ledger.accounts.add(account);
        }
      });
      if (ok) Navigator.of(context).pop();
    } on LedgerError catch (e) {
      showCwAlert(context, tr('请检查输入'), e.message);
    }
  }

  void _reconcileBalance(Account account) {
    final store = StoreScope.read(context);
    try {
      if (_name.text != account.name || _normalized(_opening.text) != Money.input(account.openingBalance) || _archived != account.archived) {
        throw LedgerError(tr('请先保存账户资料，再生成余额调整。'));
      }
      final actual = Money.parse(_normalized(_reconcile.text));
      final difference = actual - store.ledger.balance(account.id);
      if (difference == 0) throw LedgerError(tr('余额已经一致，无需调整。'));
      final entry = Entry(kind: EntryKind.adjustment, amount: difference, accountID: account.id, note: tr('余额核对调整'));
      if (store.save(entry)) Navigator.of(context).pop();
    } on LedgerError catch (e) {
      showCwAlert(context, tr('请检查输入'), e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final account = widget.account;
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true, signed: true);
    return SheetScaffold(
      title: account == null ? tr('新账户') : tr('管理账户'),
      trailingLabel: tr('保存'),
      onTrailing: _save,
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.all(18), children: [
        FormSection(
          title: tr('账户资料'),
          footer: tr('期初余额是记账开始前的余额，不是当前余额。修改会影响所有时期的账面余额。归档不会删除任何记录。'),
          children: [
            LabeledField(icon: 'credit-card', label: tr('账户名称'), controller: _name, hint: tr('例如 招商银行'), alignEnd: true),
            LabeledField(
              icon: 'piggy-bank',
              label: tr('期初余额（{code}）', {'code': store.ledger.currency}),
              controller: _opening,
              hint: '0',
              alignEnd: true,
              keyboardType: numberKeyboard,
              inputFormatters: [MoneyInputFormatter(signed: true)],
            ),
            FormRow(icon: 'coins', label: tr('币种'), trailing: CurrencyLabel(StoreScope.of(context).ledger.currency)),
            FormRow(
              icon: 'archive',
              label: tr('归档账户'),
              trailing: IOSSwitch(value: _archived, onChanged: (v) => setState(() => _archived = v)),
            ),
          ],
        ),
        if (account != null) ...[
          const SizedBox(height: 18),
          FormSection(
            title: tr('核对当前余额'),
            footer: tr('调整只改变账户余额，不影响收支报表。账户资料修改尚未保存时，请先保存再调整。'),
            children: [
              FormRow(
                icon: 'wallet',
                label: tr('当前账面'),
                trailing: AmountText(store.ledger.balance(account.id), size: 15, weight: FontWeight.w600, color: p.ink),
              ),
              KeyedSubtree(
                key: _reconcileKey,
                child: LabeledField(
                  icon: 'equal',
                  label: tr('实际余额（{code}）', {'code': store.ledger.currency}),
                  controller: _reconcile,
                  hint: tr('可为负'),
                  alignEnd: true,
                  keyboardType: numberKeyboard,
                  inputFormatters: [MoneyInputFormatter(signed: true)],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              FormRow(
                icon: 'check',
                label: tr('生成余额调整记录'),
                onTap: _reconcile.text.isEmpty ? null : () => _reconcileBalance(account),
              ),
            ],
          ),
        ],
      ]),
    );
  }
}

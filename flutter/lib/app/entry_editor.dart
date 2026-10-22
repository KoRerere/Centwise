import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/money.dart';
import 'components.dart';
import 'icons.dart';
import 'motion.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

class _AllocationDraft {
  _AllocationDraft({required this.categoryID, required String amount}) : amount = TextEditingController(text: amount);
  final String id = newId();
  String categoryID;
  final TextEditingController amount;
}

/// "记一笔" / "编辑账单". Main path: amount (in-app number pad, shown by default) → category → save.
class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, this.entry});
  final Entry? entry;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  Entry? get original => widget.entry;

  late EntryKind _kind = original?.kind ?? EntryKind.expense;
  late String _amount = original == null ? '' : Money.input(original!.amount.abs());
  late DateTime _date = original?.date ?? DateTime.now();

  /// The user picked a date. Until then a new entry's date follows the clock, so leaving the editor open
  /// across midnight still books it on the new "today".
  bool _dateEdited = false;
  late String _accountID = original?.accountID ?? '';
  late String _destinationID = original?.destinationID ?? '';
  late List<_AllocationDraft> _allocations = [
    for (final a in original?.allocations ?? const <Allocation>[]) _AllocationDraft(categoryID: a.categoryID, amount: Money.input(a.amount))
  ];
  late final TextEditingController _note = TextEditingController(text: original?.note ?? '');
  late final TextEditingController _payee = TextEditingController(text: original?.payee ?? '');
  late bool _pending = original?.pending ?? false;
  late bool _reversal = (original?.amount ?? 0) < 0;
  late bool _more = original != null &&
      (original!.allocations.length > 1 || original!.pending || original!.amount < 0 || original!.payee.isNotEmpty || original!.needsReview);

  /// Copilot-style in-app number pad for the amount; shown by default for a new entry.
  late bool _keypadVisible = original == null;
  final FocusNode _noteFocus = FocusNode();
  final FocusNode _payeeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final store = StoreScope.read(context);
    if (_accountID.isEmpty) _accountID = _availableAccounts(store).firstOrNullValue?.id ?? '';
    if (_allocations.isEmpty && _isFlow(_kind)) _allocations = [_AllocationDraft(categoryID: '', amount: _signedInput)];
    _initialSnapshot = _snapshot();
    _initialDay = DateUtils.dateOnly(_date);
    for (final node in [_noteFocus, _payeeFocus]) {
      node.addListener(() {
        // A text field took the keyboard: put the number pad away.
        if (node.hasFocus && _keypadVisible) setState(() => _keypadVisible = false);
      });
    }
  }

  @override
  void dispose() {
    _limitTimer?.cancel();
    _note.dispose();
    _payee.dispose();
    _noteFocus.dispose();
    _payeeFocus.dispose();
    for (final draft in _allocations) {
      draft.amount.dispose();
    }
    super.dispose();
  }

  late final String _initialSnapshot;
  late final DateTime _initialDay;

  /// Everything the user can change except the date, which is compared separately (see [_isDirty]).
  String _snapshot() => [
        _kind.name,
        _amount,
        _accountID,
        _destinationID,
        for (final a in _allocations) '${a.categoryID}=${a.amount.text}',
        _note.text,
        _payee.text,
        _pending,
        _reversal,
      ].join('\u0001');

  /// Something was typed or changed since the editor opened. A date that only moved because the day
  /// rolled over doesn't count.
  bool get _isDirty =>
      _snapshot() != _initialSnapshot || (_dateEdited && DateUtils.dateOnly(_date) != _initialDay);

  /// The date that will be saved: a new entry follows today until a date is picked.
  DateTime get _effectiveDate {
    if (original != null || _dateEdited || _isToday(_date)) return _date;
    final now = DateTime.now();
    return now;
  }

  Future<void> _confirmClose() async {
    final navigator = Navigator.of(context);
    if (await confirmDiscardChanges(context)) navigator.pop();
  }

  static bool _isFlow(EntryKind kind) => kind == EntryKind.income || kind == EntryKind.expense;

  List<Account> _availableAccounts(LedgerStore store) =>
      store.ledger.accounts.where((a) => !a.archived || a.id == original?.accountID).toList();

  List<LedgerCategory> _categories(LedgerStore store) => store.ledger.categories.where((c) => c.kind == _kind).toList();

  String get _signedInput => _reversal && !_amount.startsWith('-') ? '-$_amount' : _amount;

  String get _selectedCategoryID => _allocations.length == 1 ? _allocations.first.categoryID : '';

  /// "1234567.8" → "1,234,567.8" for display; the editable text stays plain.
  static String _grouped(String text) {
    final dot = text.indexOf('.');
    final whole = dot < 0 ? text : text.substring(0, dot);
    final rest = dot < 0 ? '' : text.substring(dot);
    final out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
      out.write(whole[i]);
    }
    return '$out$rest';
  }

  bool _limitHint = false;
  Timer? _limitTimer;

  /// A key press the keypad refused (11th digit, 3rd decimal): say why for a moment.
  void _onLimit() {
    _limitTimer?.cancel();
    setState(() => _limitHint = true);
    _limitTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _limitHint = false);
    });
  }

  String? get _amountError {
    if (_amount.isEmpty || _amount.endsWith('.')) return null;
    try {
      Money.parse(_signedInput);
      return null;
    } on LedgerError catch (e) {
      return e.message;
    }
  }

  bool _canSave(LedgerStore store) {
    final int cents;
    try {
      cents = Money.parse(_signedInput);
    } on LedgerError {
      return false;
    }
    if (!_availableAccounts(store).any((a) => a.id == _accountID)) return false;
    if (_kind == EntryKind.transfer) return cents > 0 && _destinationID.isNotEmpty && _destinationID != _accountID;
    if (_kind == EntryKind.adjustment) return true;
    if (cents == 0 && original?.amount != 0) return false;
    // One line without a category is fine: it is saved under "其他". Splits need every category.
    if (_allocations.length == 1) return true;
    return _allocations.isNotEmpty && _allocations.every((a) => a.categoryID.isNotEmpty);
  }

  void _synchronizeSingleAllocation() {
    if (_allocations.length == 1) _allocations.first.amount.text = _signedInput;
  }

  void _setAmount(String value) {
    setState(() {
      _amount = value;
      _synchronizeSingleAllocation();
    });
  }

  Future<void> _selectKind(EntryKind next) async {
    if (next == _kind) return;
    if (_allocations.length > 1) {
      final ok = await confirmDestructive(context, tr('切换类型会重设当前分类分摊。金额和备注会保留。'), tr('确认切换并重设分摊'));
      if (!ok) return;
    }
    setState(() {
      _kind = next;
      _reversal = false;
      for (final draft in _allocations) {
        draft.amount.dispose();
      }
      _allocations = _isFlow(next) ? [_AllocationDraft(categoryID: '', amount: _amount)] : [];
      FocusScope.of(context).unfocus();
      _keypadVisible = true;
    });
  }

  void _selectCategory(String id, {_AllocationDraft? target}) {
    setState(() {
      if (target != null) {
        target.categoryID = id;
      } else if (_allocations.length <= 1) {
        for (final draft in _allocations) {
          draft.amount.dispose();
        }
        _allocations = [_AllocationDraft(categoryID: id, amount: _signedInput)];
      }
    });
  }

  List<LedgerCategory> _quickCategories(LedgerStore store) {
    final usage = <String, int>{};
    for (final entry in store.ledger.entries) {
      if (entry.kind != _kind) continue;
      for (final allocation in entry.allocations) {
        usage[allocation.categoryID] = (usage[allocation.categoryID] ?? 0) + 1;
      }
    }
    final categories = _categories(store);
    final indexed = [for (var i = 0; i < categories.length; i++) (i, categories[i])];
    indexed.sort((a, b) {
      final lhs = usage[a.$2.id] ?? 0, rhs = usage[b.$2.id] ?? 0;
      return lhs == rhs ? a.$1.compareTo(b.$1) : rhs.compareTo(lhs);
    });
    final result = indexed.take(8).map((e) => e.$2).toList();
    final selected = categories.where((c) => c.id == _selectedCategoryID).firstOrNullValue;
    if (selected != null && !result.any((c) => c.id == selected.id)) {
      if (result.length == 8) result.removeLast();
      result.add(selected);
    }
    return result;
  }

  Future<void> _chooseCategory({_AllocationDraft? target}) async {
    final store = StoreScope.read(context);
    FocusScope.of(context).unfocus();
    final id = await showCwSheet<String>(
      context,
      (_) => StoreScope(
        store: store,
        child: _CategoryChooser(categories: _categories(store), selectedID: target?.categoryID ?? _selectedCategoryID),
      ),
    );
    if (id != null) _selectCategory(id, target: target);
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    var picked = _effectiveDate;
    final p = Palette.of(context);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 300,
        decoration: BoxDecoration(color: p.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
        child: SafeArea(
          top: false,
          child: Column(children: [
            Row(children: [
              CupertinoButton(
                child: Text(tr('今天')),
                onPressed: () {
                  final now = DateTime.now();
                  picked = DateTime(now.year, now.month, now.day, picked.hour, picked.minute, picked.second);
                  Navigator.of(context).pop();
                },
              ),
              const Spacer(),
              CupertinoButton(child: Text(tr('完成')), onPressed: () => Navigator.of(context).pop()),
            ]),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: picked,
                minimumDate: DateTime(1970, 1, 1),
                maximumDate: DateTime(2099, 12, 31),
                onDateTimeChanged: (value) => picked = DateTime(value.year, value.month, value.day, picked.hour, picked.minute, picked.second),
              ),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      if (DateUtils.dateOnly(picked) != DateUtils.dateOnly(_effectiveDate)) _dateEdited = true;
      _date = picked;
    });
  }

  void _save() {
    final store = StoreScope.read(context);
    try {
      final cents = Money.parse(_signedInput);
      if (_kind == EntryKind.transfer && cents <= 0) throw LedgerError(tr('转账金额必须大于零。'));
      if (_isFlow(_kind) && cents == 0 && original?.amount != 0) throw LedgerError(tr('收支金额不能为零。'));
      if (_isFlow(_kind) && _allocations.length == 1 && _allocations.first.categoryID.isEmpty) {
        // No category picked: file it under "其他", creating that category the first time.
        var other = store.otherCategory(_kind);
        if (other == null) {
          final created = LedgerCategory(
              name: _kind == EntryKind.income ? tr('其他收入') : tr('其他'), kind: _kind, symbol: 'ellipsis');
          if (!store.commit((ledger) => ledger.categories.add(created))) return;
          other = created;
        }
        _allocations.first.categoryID = other.id;
      }
      final split = _isFlow(_kind)
          ? [
              for (final draft in _allocations)
                Allocation(
                  categoryID: draft.categoryID,
                  amount: _allocations.length == 1 ? cents : Money.parse(draft.amount.text.replaceAll('。', '.').replaceAll('．', '.')),
                )
            ]
          : <Allocation>[];
      final entry = Entry(
        id: original?.id,
        kind: _kind,
        amount: cents,
        date: _effectiveDate,
        accountID: _accountID,
        destinationID: _kind == EntryKind.transfer ? _destinationID : null,
        allocations: split,
        note: _note.text,
        payee: _payee.text,
        pending: _pending,
        legacyType: original?.legacyType,
        needsReview: original?.needsReview ?? false,
      );
      final test = store.ledger.copy();
      test.entries.removeWhere((e) => e.id == entry.id);
      test.entries.add(entry);
      test.validate();
      if (store.save(entry)) Navigator.of(context).pop();
    } on LedgerError catch (e) {
      showCwAlert(context, tr('请检查输入'), e.message);
    }
  }

  Future<void> _delete() async {
    final store = StoreScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmDestructive(context, tr('删除这笔记录？删除后可在几秒内撤销。'), tr('删除记录'));
    // Deleted through the store, so "已删除账单 · 撤销" appears once the sheet closes.
    if (ok && store.deleteEntry(original!)) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final accounts = _availableAccounts(store);
    // Cancel, a tap outside the sheet and swiping it down all go through maybePop, so this one check
    // covers them: with unsaved input, ask before throwing it away; otherwise just close.
    // canPop stays false and the decision is made at that moment, because typing in a text field
    // doesn't rebuild this widget.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isDirty) {
          _confirmClose();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Padding(
      // Keep the save bar (with 账户 · 日期) above the system keyboard while the note is being typed.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SheetScaffold(
        title: original == null ? tr('记一笔') : tr('编辑账单'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _typeSelector(),
            const SizedBox(height: 12),
            _amountDisplay(p),
            // 备注 sits right under the amount so it is found on first open (账户 and 日期 live in the bar
            // above the save button, in view with the keypad open).
            const SizedBox(height: 14),
            CwCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Column(children: [
                if (_kind == EntryKind.transfer) ...[
                  _detailRow(p, tr('转入账户'), 'arrow-down-to-line',
                      MenuPicker<String>(
                        value: _destinationID.isEmpty ? null : _destinationID,
                        placeholder: tr('选择转入账户'),
                        options: [for (final a in store.ledger.accounts.where((a) => !a.archived && a.id != _accountID)) a.id],
                        label: store.accountName,
                        onChanged: (id) => setState(() => _destinationID = id),
                      )),
                  Divider(height: 1, color: p.track),
                ],
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 15), child: LIcon('text-align-start', size: 17, color: p.muted)),
                  const SizedBox(width: 10),
                  Expanded(child: FormTextField(controller: _note, hint: tr('备注（可选）'), maxLines: 3, focusNode: _noteFocus)),
                ]),
              ]),
            ),
            if (_isFlow(_kind)) ...[const SizedBox(height: 18), _categorySection(store, p)],
            const SizedBox(height: 18),
            _advanced(p),
            if (original != null) ...[
              const SizedBox(height: 18),
              CwCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Pressable(
                  onTap: _delete,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 50),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      LIcon('trash', size: 17, color: p.over),
                      const SizedBox(width: 8),
                      Text(tr('删除这笔记录'), style: cw(15, weight: FontWeight.w600, color: p.over)),
                    ]),
                  ),
                ),
              ),
            ],
          ],
        ),
        bottom: _bottom(store, p, accounts),
      ),
      ),
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Widget _typeSelector() {
    // 记一笔 only records spending and income; an existing 转账 / 余额调整 keeps its own type when edited.
    final types = [
      EntryKind.expense,
      EntryKind.income,
      if (original?.kind == EntryKind.transfer) EntryKind.transfer,
      if (original?.kind == EntryKind.adjustment) EntryKind.adjustment,
    ];
    return CapsuleSegments<EntryKind>(values: types, selected: _kind, label: (k) => k.title, onChanged: _selectKind);
  }

  Widget _amountDisplay(Palette p) {
    final tint = _reversal ? p.income : (_kind == EntryKind.income ? p.income : (_kind == EntryKind.transfer ? p.accent : p.ink));
    final large = _amount.length <= 9;
    final label = _reversal ? (_kind == EntryKind.adjustment ? tr('减少余额') : tr('退款 / 冲销金额')) : tr('{kind}金额', {'kind': _kind.title});
    return Column(children: [
      Text(label, style: cw(13, color: p.muted)),
      const SizedBox(height: 2),
      Pressable(
        semanticLabel: tr('金额 {amount}，轻点以用数字键盘输入', {'amount': _amount.isEmpty ? '0' : _amount}),
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _keypadVisible = true);
        },
        child: SizedBox(
          height: 64,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
              Text(_reversal ? '−${Money.symbol}' : Money.symbol, style: cw(24, weight: FontWeight.w700, color: tint, brand: true)),
              const SizedBox(width: 2),
              Text(_amount.isEmpty ? '0' : _grouped(_amount),
                  style: cw(large ? 54 : 38, weight: FontWeight.w700, color: _amount.isEmpty ? p.muted.withValues(alpha: 0.6) : tint, brand: true)),
              if (_keypadVisible) ...[const SizedBox(width: 3), _BlinkingCaret(height: large ? 46 : 34, color: tint)],
            ]),
          ),
        ),
      ),
      if (_amountError != null) Text(_amountError!, textAlign: TextAlign.center, style: cw(12, color: p.over)),
      AnimatedSwitcher(
        duration: IOSMotion.snappyCurve.duration,
        child: _limitHint
            ? Text(tr('最多 10 位整数、2 位小数'), key: const ValueKey('limit'), textAlign: TextAlign.center, style: cw(12, color: p.warning))
            : const SizedBox(key: ValueKey('none'), height: 0),
      ),
    ]);
  }

  Widget _categorySection(LedgerStore store, Palette p) {
    if (_allocations.length > 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardCaption(tr('分类')),
        const SizedBox(height: 12),
        Pressable(
          onTap: () => setState(() => _more = true),
          child: CwCard(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              LIcon('split', size: 16, color: p.accent),
              const SizedBox(width: 6),
              Text(tr('{n} 个分类分摊 · 编辑', {'n': _allocations.length}), style: cw(14, weight: FontWeight.w600, color: p.accent)),
            ]),
          ),
        ),
      ]);
    }
    final quick = _quickCategories(store);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(tr('分类'), trailing: tr('全部分类'), onTap: () => _chooseCategory()),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
        children: [
          for (final category in quick)
            Builder(builder: (context) {
              final selected = _selectedCategoryID == category.id;
              final tint = categoryTint(category.id);
              return Pressable(
                selected: selected,
                semanticLabel: category.name,
                onTap: () => _selectCategory(category.id),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Selected keeps its own icon: a thin ring plus a small check, so it stays recognisable.
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      AnimatedContainer(
                        duration: IOSMotion.snappyCurve.duration,
                        curve: IOSMotion.snappyCurve,
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: selected ? 0.2 : 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? tint : Colors.transparent, width: 1.5),
                        ),
                        child: Center(child: CategoryIcon(category, size: 20, color: tint)),
                      ),
                      if (selected)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(color: tint, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                            child: const Center(child: LIcon('check', size: 10, color: Colors.white, strokeWidth: 3.5)),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 5),
                  Text(category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cw(12, weight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? p.ink : p.muted)),
                ]),
              );
            }),
        ],
      ),
      if (_selectedCategoryID.isEmpty)
        Text(_amount.isEmpty ? tr('输入金额，再选一个分类。') : tr('不选分类会记入“其他”。'), style: cw(12, color: p.muted)),
    ]);
  }

  Widget _detailRow(Palette p, String label, String icon, Widget trailing) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        LIcon(icon, size: 17, color: p.muted),
        const SizedBox(width: 10),
        Text(label, style: cw(15, weight: FontWeight.w600, color: p.ink)),
        const Spacer(),
        trailing,
      ]),
    );
  }

  Widget _advanced(Palette p) {
    final reversalLabel = _kind == EntryKind.adjustment ? tr('减少余额') : tr('退款 / 冲销');
    return CwCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Pressable(
          onTap: () => setState(() => _more = !_more),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(children: [
              Text(tr('更多选项'), style: cw(15, weight: FontWeight.w600, color: p.ink)),
              const Spacer(),
              if (!_more) Text(tr('分摊 · 交易对象 · 待入账'), style: cw(12, color: p.muted)),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: _more ? 0.25 : 0,
                duration: IOSMotion.snappyCurve.duration,
                curve: IOSMotion.snappyCurve,
                child: LIcon('chevron-right', size: 16, color: p.muted),
              ),
            ]),
          ),
        ),
        if (_more) ...[
          if (_kind != EntryKind.transfer) ...[
            _switchRow(p, reversalLabel, _reversal, (v) => setState(() {
                  _reversal = v;
                  _synchronizeSingleAllocation();
                })),
            if (_reversal)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('输入正数金额，保存时按负数记入原类型。多分类分摊仍需核对各项正负金额。'), style: cw(12, color: p.muted)),
              ),
          ],
          _switchRow(p, tr('待入账'), _pending, (v) => setState(() => _pending = v)),
          Row(children: [
            LIcon('store', size: 17, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: FormTextField(controller: _payee, hint: tr('交易对象（可选）'), focusNode: _payeeFocus)),
          ]),
          if (_isFlow(_kind)) _splitOptions(p),
          if (original?.legacyType != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Money Pro 源类型 {type}', {'type': original!.legacyType}) + (original!.needsReview ? ' · ${tr('待核对')}' : ''), style: cw(12, color: p.muted)),
            ),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  Widget _switchRow(Palette p, String label, bool value, ValueChanged<bool> onChanged) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          Expanded(child: Text(label, style: cw(15, weight: FontWeight.w400, color: p.ink))),
          Switch.adaptive(value: value, onChanged: onChanged),
        ]),
      );

  /// What stops a split from saving, said specifically: 已分摊 / 剩余 or 超出, then the first line problem.
  Widget _splitStatus(LedgerStore store, Palette p) {
    int? total;
    try {
      total = Money.parse(_signedInput);
    } on LedgerError {
      total = null;
    }
    var sum = 0;
    final problems = <String>[];
    for (var i = 0; i < _allocations.length; i++) {
      final draft = _allocations[i];
      final n = i + 1;
      if (draft.categoryID.isEmpty) problems.add(tr('第 {n} 行还没选分类', {'n': n}));
      try {
        final cents = Money.parse(draft.amount.text.trim().isEmpty ? '0' : draft.amount.text.trim());
        if (cents == 0) problems.add(tr('第 {n} 行金额为 0', {'n': n}));
        sum += cents;
      } on LedgerError {
        problems.add(tr('第 {n} 行金额格式不对', {'n': n}));
      }
    }
    final ids = [for (final d in _allocations) if (d.categoryID.isNotEmpty) d.categoryID];
    if (ids.toSet().length != ids.length) problems.add(tr('有重复的分类'));
    final lines = <Widget>[];
    if (total != null) {
      final diff = total - sum;
      final balance = diff == 0
          ? tr('已分摊 {sum} · 与总额一致', {'sum': Money.text(sum)})
          : diff > 0
              ? tr('已分摊 {sum} · 还剩 {left}', {'sum': Money.text(sum), 'left': Money.text(diff)})
              : tr('已分摊 {sum} · 超出 {over}', {'sum': Money.text(sum), 'over': Money.text(-diff)});
      lines.add(Text(balance, style: cw(12, weight: FontWeight.w600, color: diff == 0 ? p.under : p.over)));
    }
    if (problems.isNotEmpty) lines.add(Text(problems.first, style: cw(12, color: p.over)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  Widget _splitOptions(Palette p) {
    final store = StoreScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_allocations.length > 1) ...[
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _splitStatus(store, p),
        ),
        for (final draft in _allocations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Pressable(
                  onTap: () => _chooseCategory(target: draft),
                  child: Text(store.category(draft.categoryID)?.name ?? tr('选择分类'),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(15, weight: FontWeight.w600, color: p.accent)),
                ),
              ),
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: p.canvas, borderRadius: BorderRadius.circular(12)),
                child: FormTextField(
                  controller: draft.amount,
                  hint: tr('金额'),
                  textAlign: TextAlign.right,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                ),
              ),
              Pressable(
                semanticLabel: tr('移除这个分摊'),
                onTap: () => setState(() {
                  _allocations.remove(draft);
                  draft.amount.dispose();
                }),
                child: Padding(padding: const EdgeInsets.all(8), child: LIcon('circle-x', size: 18, color: p.over)),
              ),
            ]),
          ),
      ],
      Pressable(
        onTap: () => setState(() {
          if (_allocations.isEmpty) _allocations.add(_AllocationDraft(categoryID: '', amount: _signedInput));
          _allocations.add(_AllocationDraft(categoryID: '', amount: '0'));
        }),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(children: [
            LIcon('plus', size: 16, color: p.accent, strokeWidth: 2.5),
            const SizedBox(width: 6),
            Text(tr('添加分摊分类'), style: cw(15, weight: FontWeight.w600, color: p.accent)),
          ]),
        ),
      ),
    ]);
  }

  /// "钱包 · 今天": the account and the date, each tappable, right above the save button.
  Widget _accountDateBar(LedgerStore store, Palette p, List<Account> accounts) {
    final date = _effectiveDate;
    final dateLabel = DayHeading.label(date) == tr('今天') || DayHeading.label(date) == tr('昨天')
        ? DayHeading.label(date)
        : (date.year == DateTime.now().year ? fmtMonthDay(date) : fmtYMD(date));
    final chipStyle = cw(14, weight: FontWeight.w600, color: p.ink);
    return SizedBox(
      height: 32,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        LIcon(_kind == EntryKind.transfer ? 'arrow-up-right' : 'credit-card', size: 15, color: p.muted),
        const SizedBox(width: 5),
        Flexible(
          child: PopupMenuButton<String>(
            tooltip: _kind == EntryKind.transfer ? tr('转出账户') : tr('账户'),
            initialValue: _accountID.isEmpty ? null : _accountID,
            color: p.card,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            position: PopupMenuPosition.over,
            onSelected: (id) => setState(() {
              _accountID = id;
              if (_destinationID == id) _destinationID = '';
            }),
            itemBuilder: (context) => [
              for (final a in accounts)
                PopupMenuItem<String>(
                  value: a.id,
                  child: Row(children: [
                    Expanded(child: Text(a.name, style: cw(15, weight: FontWeight.w400, color: p.ink))),
                    if (a.id == _accountID) LIcon('check', size: 16, color: p.accent),
                  ]),
                ),
            ],
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(_accountID.isEmpty ? tr('选择账户') : store.accountName(_accountID),
                    style: chipStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 2),
              LIcon('chevron-down', size: 14, color: p.muted),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('·', style: cw(14, weight: FontWeight.w700, color: p.muted)),
        ),
        Pressable(
          semanticLabel: tr('日期 {date}，轻点修改', {'date': fmtYMD(date)}),
          onTap: _pickDate,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LIcon('calendar', size: 15, color: p.muted),
            const SizedBox(width: 5),
            Text(dateLabel, style: chipStyle),
            const SizedBox(width: 2),
            LIcon('chevron-down', size: 14, color: p.muted),
          ]),
        ),
      ]),
    );
  }

  Widget _bottom(LedgerStore store, Palette p, List<Account> accounts) {
    final titles = switch (_kind) {
      EntryKind.income => (tr('收入'), tr('冲销')),
      EntryKind.adjustment => (tr('增加余额'), tr('减少余额')),
      _ => (tr('支出'), tr('退款')),
    };
    return Container(
      color: p.canvas,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, _keypadVisible ? 10 : 14 + MediaQuery.paddingOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_keypadVisible && _kind != EntryKind.transfer) ...[
              // A light text switch (支出 / 退款), bound to the same flag as the switch in 更多选项.
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final refund in const [false, true]) ...[
                  if (refund) Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('/', style: cw(13, color: p.track))),
                  Pressable(
                    selected: _reversal == refund,
                    onTap: () => setState(() {
                      _reversal = refund;
                      _synchronizeSingleAllocation();
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      child: Text(refund ? titles.$2 : titles.$1,
                          style: cw(14,
                              weight: _reversal == refund ? FontWeight.w600 : FontWeight.w400,
                              color: _reversal == refund ? p.accent : p.muted)),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 10),
            ],
            if (accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('请先在账户页创建一个有效账户。'), style: cw(12, color: p.over)),
              ),
            _accountDateBar(store, p, accounts),
            const SizedBox(height: 8),
            PrimaryBarButton(
              label: tr('保存这笔{kind}', {'kind': _kind.title}),
              tint: p.brand,
              onTap: _canSave(store) && !store.loadingFailed ? _save : null,
            ),
          ]),
        ),
        AnimatedSize(
          duration: IOSMotion.smoothCurve.duration,
          curve: IOSMotion.smoothCurve,
          child: _keypadVisible ? AmountKeypad(text: _amount, onChanged: _setAmount, onLimit: _onLimit) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret({required this.height, required this.color});
  final double height;
  final Color color;

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: _controller.value < 0.5 ? 1 : 0,
        child: Container(
          width: 3,
          height: widget.height,
          decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1.5)),
        ),
      ),
    );
  }
}

/// In-app number pad modelled on Copilot's amount entry: 1–9, decimal point, 0, delete.
/// At most two decimals and one decimal point; long-press delete clears.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.text, required this.onChanged, this.onLimit});
  final String text;
  final ValueChanged<String> onChanged;

  /// Called instead of [onChanged] when a digit or point is refused (length or precision limit).
  final VoidCallback? onLimit;

  static String apply(String text, String key) {
    if (key == 'delete') return text.isEmpty ? text : text.substring(0, text.length - 1);
    if (key == '.') {
      if (text.contains('.')) return text;
      return text.isEmpty ? '0.' : '$text.';
    }
    final dot = text.indexOf('.');
    if (dot >= 0) {
      return text.length - dot - 1 >= 2 ? text : text + key;
    }
    if (text.length >= 10) return text;
    if (text == '0') return key;
    return text + key;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', 'delete'],
    ];
    Widget key(String value) {
      final flat = value == '.' || value == 'delete';
      return Expanded(
        child: Pressable(
          semanticLabel: value == 'delete' ? tr('删除，长按清空') : (value == '.' ? tr('小数点') : value),
          onTap: () {
            final next = apply(text, value);
            if (next == text && value != 'delete' && !(value == '.' && text.contains('.'))) {
              HapticFeedback.lightImpact();
              onLimit?.call();
              return;
            }
            tick();
            onChanged(next);
          },
          onLongPress: value == 'delete'
              ? () {
                  tick();
                  onChanged('');
                }
              : null,
          child: Container(
            height: 48,
            decoration: BoxDecoration(color: flat ? Colors.transparent : p.card, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: value == 'delete'
                ? LIcon('delete', size: 22, color: p.ink, strokeWidth: 1.75)
                : Text(value, style: cw(25, weight: FontWeight.w400, color: p.ink)),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: p.track.withValues(alpha: 0.9),
      padding: EdgeInsets.fromLTRB(7, 8, 7, 10 + MediaQuery.paddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 7),
          Row(children: [
            for (var c = 0; c < rows[r].length; c++) ...[if (c > 0) const SizedBox(width: 7), key(rows[r][c])]
          ]),
        ]
      ]),
    );
  }
}

class _CategoryChooser extends StatefulWidget {
  const _CategoryChooser({required this.categories, required this.selectedID});
  final List<LedgerCategory> categories;
  final String selectedID;

  @override
  State<_CategoryChooser> createState() => _CategoryChooserState();
}

class _CategoryChooserState extends State<_CategoryChooser> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final query = _search.text.trim().toLowerCase();
    final list = widget.categories.where((c) => query.isEmpty || c.name.toLowerCase().contains(query)).toList();
    return SheetScaffold(
      title: tr('选择分类'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 6, 18, 32), children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(15), border: Border.all(color: p.cardStroke, width: 0.75)),
          child: Row(children: [
            LIcon('search', size: 17, color: p.muted),
            const SizedBox(width: 8),
            Expanded(child: FormTextField(controller: _search, hint: tr('搜索分类'), onChanged: (_) => setState(() {}))),
          ]),
        ),
        const SizedBox(height: 14),
        CwCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) Divider(height: 1, color: p.track),
              Pressable(
                onTap: () => Navigator.of(context).pop(list[i].id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Row(children: [
                    CategoryIcon(list[i], size: 18, color: categoryTint(list[i].id)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(list[i].name, style: cw(15, weight: FontWeight.w400, color: p.ink))),
                    if (list[i].id == widget.selectedID) LIcon('check', size: 17, color: p.accent, strokeWidth: 2.5),
                  ]),
                ),
              ),
            ],
            if (list.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text(tr('没有匹配的分类'), style: cw(14, color: p.muted))),
          ]),
        ),
      ]),
    );
  }
}

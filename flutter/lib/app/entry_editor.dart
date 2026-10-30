import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/money.dart';
import 'components.dart';
import 'icons.dart';
import 'motion.dart';
import 'pages/settings_page.dart';
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
  /// The category grid's pages (ten categories each), swiped left / right.
  final _categoryPages = PageController();
  int _categoryPage = 0;
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
    // A text field gaining or losing focus changes the list's bottom room (see the ListView).
    for (final node in [_noteFocus, _payeeFocus]) {
      node.addListener(() {
        if (mounted) setState(() {});
      });
    }
    for (final node in [_noteFocus, _payeeFocus]) {
      node.addListener(() {
        // A text field took the keyboard: put the number pad away, folding any typed calculation
        // ("1+12" → "13") so the saved amount always ends up a plain number.
        if (node.hasFocus && _keypadVisible) {
          setState(() => _keypadVisible = false);
          _collapseExpression();
        }
      });
    }
  }

  @override
  void dispose() {
    _limitTimer?.cancel();
    _categoryPages.dispose();
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

  /// Number runs vs operator runs, for grouping the calculation display.
  static final RegExp _tokenPattern = RegExp(r'[0-9.]+|[^0-9.]+');

  /// "1234567.8" → "1,234,567.8" for display; the editable text stays plain. Each operand of a
  /// calculation ("1234+56×2" → "1,234+56×2") is grouped on its own.
  static String _grouped(String text) {
    return [
      for (final part in _tokenPattern.allMatches(text))
        part.group(0)!.contains(RegExp('[0-9]')) ? _groupNumber(part.group(0)!) : part.group(0)!,
    ].join();
  }

  static String _groupNumber(String number) {
    final dot = number.indexOf('.');
    final whole = dot < 0 ? number : number.substring(0, dot);
    final rest = dot < 0 ? '' : number.substring(dot);
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
    if (_amount.isEmpty) return null;
    // Mid-typing: a dangling point or a waiting operator is not an error yet.
    final last = _amount.substring(_amount.length - 1);
    if (last == '.' || AmountKeypad.operators.contains(last)) return null;
    try {
      Money.parse(_signedInput);
    } on LedgerError catch (e) {
      return e.message;
    }
    if (_mustBePositive && (_typedCents ?? 1) <= 0) return tr('金额需要大于 0');
    return null;
  }

  /// What the user typed, evaluated, before 退款 / 冲销 flips its sign; null while incomplete.
  int? get _typedCents {
    try {
      return Money.parse(_amount);
    } on LedgerError {
      return null;
    }
  }

  /// Expenses and incomes are entered as a positive amount (a refund is the 退款 switch, not a
  /// negative number). Old zero-amount bills from Money Pro can still be edited as they are.
  bool get _mustBePositive => _isFlow(_kind) && !(original != null && original!.amount == 0);

  bool _canSave(LedgerStore store) {
    final int cents;
    try {
      cents = Money.parse(_signedInput);
    } on LedgerError {
      return false;
    }
    // No account yet is fine: saving adds the hidden default one (see LedgerStore.defaultAccountID).
    if (_accountID.isNotEmpty && !_availableAccounts(store).any((a) => a.id == _accountID)) return false;
    if (_kind == EntryKind.transfer) return cents > 0 && _destinationID.isNotEmpty && _destinationID != _accountID;
    if (_kind == EntryKind.adjustment) return true;
    // A zero or negative amount still lets 保存 be tapped: it then says why and keeps the editor open.
    if (_mustBePositive) return _amount.isNotEmpty;
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

  /// Closing the keypad folds a typed calculation into its result ("1+12" → "13"). An expression
  /// that doesn't evaluate (a trailing operator) is left as typed; the save button simply stays off
  /// until it is completed.
  void _collapseExpression() {
    if (!_amount.contains(RegExp(r'[+−×÷/]'))) return;
    try {
      final cents = Money.parse(_signedInput);
      // With 退款 / 冲销 on, the signed amount is the negation of what was typed.
      _setAmount(Money.input(_reversal ? -cents : cents));
    } on LedgerError {
      // Incomplete ("1+"): keep it as typed; reopening the keypad continues where it left off.
    }
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

  /// The top-level category a category belongs to (itself when it is top-level, or when its parent
  /// no longer exists).
  LedgerCategory? _topOf(LedgerStore store, String id) {
    final c = store.ledger.categoryByID(id);
    if (c == null) return null;
    final parent = c.parentID == null ? null : store.ledger.categoryByID(c.parentID!);
    return parent ?? c;
  }

  bool _hasChildren(LedgerStore store, String id) => store.ledger.categories.any((c) => c.parentID == id);

  /// The category strip shows first-level categories only: the ten most-used first (a subcategory's
  /// use counts for its parent), then every remaining one of this kind in ledger order — two rows of
  /// five are visible, the rest are a swipe to the right. Subcategories are picked from the parent.
  List<LedgerCategory> _quickCategories(LedgerStore store) {
    final usage = <String, int>{};
    for (final entry in store.ledger.entries) {
      if (entry.kind != _kind) continue;
      for (final allocation in entry.allocations) {
        final top = _topOf(store, allocation.categoryID)?.id ?? allocation.categoryID;
        usage[top] = (usage[top] ?? 0) + 1;
      }
    }
    final categories = _categories(store).where((c) => _topOf(store, c.id)?.id == c.id).toList();
    final indexed = [for (var i = 0; i < categories.length; i++) (i, categories[i])];
    indexed.sort((a, b) {
      final lhs = usage[a.$2.id] ?? 0, rhs = usage[b.$2.id] ?? 0;
      return lhs == rhs ? a.$1.compareTo(b.$1) : rhs.compareTo(lhs);
    });
    final result = indexed.take(10).map((e) => e.$2).toList();
    result.addAll(categories.where((c) => !result.contains(c)));
    return result;
  }

  Future<void> _chooseCategory({_AllocationDraft? target, String? parentID}) async {
    final store = StoreScope.read(context);
    FocusScope.of(context).unfocus();
    // Opened on one parent's subcategories, the sheet is only as tall as that list: header and
    // search (~140), the parent's own 不细分 row (~60), ~51 per subcategory, and bottom room.
    double? height;
    if (parentID != null) {
      final children = store.ledger.categories.where((c) => c.parentID == parentID).length;
      height = 140 + 60 + children * 51.0 + 40 + MediaQuery.paddingOf(context).bottom;
    }
    final id = await showCwSheet<String>(
      context,
      (_) => StoreScope(
        store: store,
        child: CategoryChooser(kind: _kind, selectedID: target?.categoryID ?? _selectedCategoryID, initialParentID: parentID),
      ),
      height: height,
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
    if (_mustBePositive && (_typedCents ?? 1) <= 0) {
      setState(() => _keypadVisible = true);
      showCwAlert(context, tr('金额需要大于 0'), tr('{kind}金额不能是负数或零，请继续编辑。要记退款，请切换到“退款”。', {'kind': _kind.title}));
      return;
    }
    try {
      final cents = Money.parse(_signedInput);
      if (_accountID.isEmpty) {
        final id = store.defaultAccountID();
        if (id == null) return;
        _accountID = id;
      }
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
      // A tap on any blank part of the form puts the keyboard away — the system one for the note,
      // and the amount keypad too (tap the amount to bring it back). Taps on controls go to them.
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_keypadVisible) {
          setState(() => _keypadVisible = false);
          // Closing the pad shows the result of a typed calculation ("25.8+12" → "37.8").
          _collapseExpression();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: AmountHardwareKeys(
        enabled: _keypadVisible,
        text: _amount,
        onChanged: _setAmount,
        onLimit: _onLimit,
        onSubmit: _canSave(store) && !store.loadingFailed ? _save : null,
        child: SheetScaffold(
        // Semantics keep the sheet's name; visually the bar carries just the ✕ — the amount display
        // below already says what this sheet is.
        title: original == null ? tr('记一笔') : tr('编辑账单'),
        titleWidget: const SizedBox.shrink(),
        // The amount starts up beside the ✕ instead of under an empty bar.
        contentUnderBar: true,
        body: ListView(clipBehavior: Clip.none,
          // Bottom clearance: the form scrolls behind the frosted bottom controls now.
          // Bottom room = the controls floating over the form: the type / date bar and save button
          // (~150), plus the number pad while it is up, so the note can always be scrolled up
          // above the pad and tapped (which brings up the system keyboard).
          // While a text field is being typed in, extra room lets it scroll up above the save bar,
          // so what's being typed stays in view over the system keyboard; it goes away afterwards.
          padding: EdgeInsets.fromLTRB(18, 34, 18,
              150 + (_keypadVisible ? 246 + MediaQuery.paddingOf(context).bottom : 0) + (_noteFocus.hasFocus || _payeeFocus.hasFocus ? 220 : 0)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            _amountDisplay(p),
            if (_isFlow(_kind)) ...[const SizedBox(height: 14), _categorySection(store, p)],
            // 备注 comes after the category (amount → category → note), still above 更多选项; 账户 and 日期
            // live in the bar above the save button, in view with the keypad open.
            const SizedBox(height: 18),
            CwCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
                ],
                // Note: a document icon and a 17 pt field on one 52 pt row (it grows to 3 lines); the pencil sits
                // on the first line's centre, so it stays put as the note wraps.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      // Lucide file-text, centred on the text's visual middle (26 pt down the row).
                      padding: const EdgeInsets.only(top: 16),
                      child: LIcon('file-text', size: 20, color: p.muted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _note,
                        focusNode: _noteFocus,
                        // Keep the field clear of the save bar floating over the bottom of the form.
                        scrollPadding: const EdgeInsets.only(bottom: 220),
                        minLines: 1,
                        maxLines: 3,
                        style: cw(IOSText.body, color: p.ink, height: 1.3).copyWith(leadingDistribution: TextLeadingDistribution.even),
                        // A fixed 22 pt line box with the leading split evenly: left to the fonts, the line
                        // height and the glyphs' place in it come out differently on the iPhone and the Mac
                        // (San Francisco vs the PingFang fallback), which is why the hint never lined up on both.
                        strutStyle: const StrutStyle(
                          fontFamily: 'CupertinoSystemText',
                          fontFamilyFallback: ['PingFang SC', 'PingFang TC'],
                          fontSize: IOSText.body,
                          height: 1.3,
                          forceStrutHeight: true,
                          leadingDistribution: TextLeadingDistribution.even,
                        ),
                        cursorColor: p.ink,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          // (52 − 22) / 2 on each side: one line sits in the middle of the row.
                          contentPadding: const EdgeInsets.symmetric(vertical: 15),
                          hintText: tr('添加备注'),
                          hintStyle: cw(IOSText.body, color: p.muted, height: 1.3).copyWith(leadingDistribution: TextLeadingDistribution.even),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
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
                      Text(tr('删除这笔记录'), style: cw(IOSText.body, weight: FontWeight.w500, color: p.over)),
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
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  /// One switch for what the bill is: 支出 / 收入 / 退款 (退款 = a spending entry reversed, the same
  /// flag as the 退款 switch in 更多选项). Editing a 转账 / 余额调整 adds that type as a fourth segment.
  Widget _typeSelector({double height = 44, double segmentWidth = 96}) {
    final modes = [
      'expense',
      'income',
      'refund',
      if (original?.kind == EntryKind.transfer) 'transfer',
      if (original?.kind == EntryKind.adjustment) 'adjustment',
    ];
    final current = switch (_kind) {
      EntryKind.expense => _reversal ? 'refund' : 'expense',
      EntryKind.income => 'income',
      EntryKind.transfer => 'transfer',
      EntryKind.adjustment => 'adjustment',
    };
    String label(String m) => switch (m) {
          'expense' => EntryKind.expense.title,
          'income' => EntryKind.income.title,
          'refund' => tr('退款'),
          'transfer' => EntryKind.transfer.title,
          _ => EntryKind.adjustment.title,
        };
    Future<void> pick(String m) async {
      final kind = switch (m) {
        'income' => EntryKind.income,
        'transfer' => EntryKind.transfer,
        'adjustment' => EntryKind.adjustment,
        _ => EntryKind.expense,
      };
      await _selectKind(kind);
      if (!mounted || _kind != kind) return; // switch cancelled
      final refund = m == 'refund';
      if (_reversal != refund) {
        setState(() {
          _reversal = refund;
          _synchronizeSingleAllocation();
        });
      }
    }

    return SizedBox(
      width: segmentWidth * modes.length,
      child: CapsuleSegments<String>(values: modes, selected: current, label: label, onChanged: pick, height: height),
    );
  }

  Widget _amountDisplay(Palette p) {
    final tint = _reversal ? p.income : (_kind == EntryKind.income ? p.income : (_kind == EntryKind.transfer ? p.accent : p.ink));
    final large = _amount.length <= 9;
    final label = _reversal ? (_kind == EntryKind.adjustment ? tr('减少余额') : tr('退款 / 冲销金额')) : tr('{kind}金额', {'kind': _kind.title});
    return Column(children: [
      Text(label, style: cw(IOSText.footnote, color: p.muted)),
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
              if (_keypadVisible) ...[const SizedBox(width: 3), _BlinkingCaret(fontSize: large ? 54 : 38, color: tint)],
            ]),
          ),
        ),
      ),
      if (_amountError != null) Text(_amountError!, textAlign: TextAlign.center, style: cw(IOSText.footnote, color: p.over)),
      AnimatedSwitcher(
        duration: IOSMotion.snappyCurve.duration,
        child: _limitHint
            ? Text(tr('最多 10 位整数、2 位小数'), key: const ValueKey('limit'), textAlign: TextAlign.center, style: cw(IOSText.footnote, color: p.warning))
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
              Text(tr('{n} 个分类分摊 · 编辑', {'n': _allocations.length}), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.accent)),
            ]),
          ),
        ),
      ]);
    }
    final quick = _quickCategories(store);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(tr('分类'), trailing: tr('全部分类'), onTap: () => _chooseCategory()),
      const SizedBox(height: 12),
      // Two rows of five visible (the most-used first), reading left-to-right; the strip scrolls
      // horizontally through the remaining categories.
      SizedBox(
        height: 164,
        child: LayoutBuilder(builder: (context, constraints) {
          final chunkWidth = (constraints.maxWidth - 4 * 8) / 5;
          final chosen = _selectedCategoryID.isEmpty ? null : store.ledger.categoryByID(_selectedCategoryID);
          Widget tile(LedgerCategory category) {
            // A parent counts as selected when one of its subcategories is; its label then names
            // the subcategory, so the choice stays visible on the strip.
            final selected = chosen != null && (chosen.id == category.id || chosen.parentID == category.id);
            final label = selected && chosen.id != category.id ? chosen.name : category.name;
            final tint = categoryTint(category.id);
            final opensList = _hasChildren(store, category.id);
            return Pressable(
              selected: selected,
              semanticLabel: category.name,
              onTap: opensList ? () => _chooseCategory(parentID: category.id) : () => _selectCategory(category.id),
              child: SizedBox(
                height: 76,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // Selected keeps its own icon: a thin ring plus a small check, so it stays recognisable.
                  // Picking it gives the disc a small spring pop.
                  SelectPop(
                    selected: selected,
                    child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      AnimatedContainer(
                        duration: IOSMotion.snappyCurve.duration,
                        curve: IOSMotion.snappyCurve,
                        width: 48,
                        height: 48,
                        // Trackly-style: the emoji on a plain round disc, no colour tint; selection is a
                        // black ring and a black check, so colour stays with the emoji.
                        decoration: BoxDecoration(
                          color: p.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: selected ? p.ink : Colors.transparent, width: 1.5),
                        ),
                        child: Center(child: CategoryIcon(category, size: 24, color: tint)),
                      ),
                      if (selected)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                            child: Center(child: LIcon('check', size: 10, color: p.onBrand, strokeWidth: 3.5)),
                          ),
                        ),
                    ]),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cw(IOSText.footnote, weight: selected ? FontWeight.w700 : FontWeight.w400, color: selected ? p.ink : p.muted)),
                ]),
              ),
            );
          }

          // Pages of ten (five columns × two rows, most-used first), swiped sideways like the iOS
          // home screen; dots below show where you are.
          final pages = (quick.length / 10).ceil();
          return PageView.builder(
            controller: _categoryPages,
            itemCount: pages,
            onPageChanged: (i) => setState(() => _categoryPage = i),
            itemBuilder: (context, page) => Column(children: [
              for (final r in const [0, 5])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    for (var c = 0; c < 5; c++) ...[
                      if (c > 0) const SizedBox(width: 8),
                      SizedBox(
                        width: chunkWidth,
                        child: page * 10 + r + c < quick.length ? tile(quick[page * 10 + r + c]) : const SizedBox(height: 76),
                      ),
                    ],
                  ]),
                ),
            ]),
          );
        }),
      ),
      if ((quick.length / 10).ceil() > 1) ...[
        // Breathing room between the last row's labels and the page dots.
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < (quick.length / 10).ceil(); i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _categoryPage ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _categoryPage ? p.ink : p.muted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ],
    ]);
  }

  Widget _detailRow(Palette p, String label, String icon, Widget trailing) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        LIcon(icon, size: 17, color: p.muted),
        const SizedBox(width: 10),
        Text(label, style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
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
              Text(tr('更多选项'), style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
              const Spacer(),
              if (!_more) Text(tr('分摊 · 交易对象 · 待入账'), style: cw(IOSText.footnote, color: p.muted)),
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
                child: Text(tr('输入正数金额，保存时按负数记入原类型。多分类分摊仍需核对各项正负金额。'), style: cw(IOSText.footnote, color: p.muted)),
              ),
          ],
          _switchRow(p, tr('待入账'), _pending, (v) => setState(() => _pending = v)),
          Row(children: [
            LIcon('store', size: 17, color: p.muted),
            const SizedBox(width: 10),
            Expanded(child: FormTextField(controller: _payee, hint: tr('交易对象（可选）'), focusNode: _payeeFocus, scrollPadding: const EdgeInsets.only(bottom: 220))),
          ]),
          if (_isFlow(_kind)) _splitOptions(p),
          if (original?.legacyType != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Money Pro 源类型 {type}', {'type': original!.legacyType}) + (original!.needsReview ? ' · ${tr('待核对')}' : ''), style: cw(IOSText.footnote, color: p.muted)),
            ),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  Widget _switchRow(Palette p, String label, bool value, ValueChanged<bool> onChanged) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          Expanded(child: Text(label, style: cw(IOSText.body, weight: FontWeight.w400, color: p.ink))),
          IOSSwitch(value: value, onChanged: onChanged),
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
      lines.add(Text(balance, style: cw(IOSText.footnote, weight: FontWeight.w600, color: diff == 0 ? p.under : p.over)));
    }
    if (problems.isNotEmpty) lines.add(Text(problems.first, style: cw(IOSText.footnote, color: p.over)));
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
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.body, weight: FontWeight.w600, color: p.accent)),
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
            Text(tr('添加分摊分类'), style: cw(IOSText.body, weight: FontWeight.w600, color: p.accent)),
          ]),
        ),
      ),
    ]);
  }

  /// "[支出|收入] · 今天": the type switch and the date, each tappable where present, right above the
  /// save button. There is no account to choose: a new entry goes to the hidden default account and
  /// an edited one keeps its own.
  Widget _typeDateBar(Palette p) {
    final date = _effectiveDate;
    final dateLabel = DayHeading.label(date) == tr('今天') || DayHeading.label(date) == tr('昨天')
        ? DayHeading.label(date)
        : (date.year == DateTime.now().year ? fmtMonthDay(date) : fmtYMD(date));
    final chipStyle = cw(IOSText.subheadline, weight: FontWeight.w600, color: p.ink);
    return SizedBox(
      height: 34,
      // 支出 / 收入 / 退款 on the left, the date on the right.
      child: Row(children: [
        // Four segments (editing a transfer / adjustment) can exceed a narrow phone, so scale down.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: _typeSelector(height: 34, segmentWidth: 64),
            ),
          ),
        ),
        const SizedBox(width: 12),
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
    // The form scrolls BEHIND these controls now: a frosted backdrop blurs whatever passes under
    // them, and a wash band reaching 46 pt above dissolves incoming rows instead of hard-clipping
    // them at the controls' top edge. The keypad keeps its own track fill on top of the frost.
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, _keypadVisible ? 10 : 14 + MediaQuery.paddingOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _typeDateBar(p),
            // The type / date bar sits a little higher, with more air above the save button.
            const SizedBox(height: 18),
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
      ]);
    // Blank parts of the bottom controls swallow taps, so tapping between the buttons doesn't fold
    // the keypad away (that's for the form above).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Stack(clipBehavior: Clip.none, children: [
      // Frosted backdrop: whatever scrolls behind the controls is blurred and washed toward the
      // sheet colour, so it never competes with the buttons. (SheetScaffold paints these controls
      // before the bar's native ✕, so the blur can see the content on iPhone too.)
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(color: p.canvas.withValues(alpha: 0.72)),
            ),
          ),
        ),
      ),
      content,
      // Dissolve band above the controls: a canvas wash with a blur strip along its lower edge.
      Positioned(
        left: 0,
        right: 0,
        top: -46,
        height: 46,
        child: IgnorePointer(
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 18,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.canvas.withValues(alpha: 0), p.canvas.withValues(alpha: 0.72)],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]),
    );
  }
}

/// Text caret for the amount, lined up with the digits like UIKit's: it sits in a baseline row, so its
/// bottom lands on the baseline; it is moved down a little and made a little taller than the digits,
/// so it runs from just below the baseline to just above the figures.
/// The amount caret for other editors that copy 记一笔's amount display (e.g. 新增订阅).
class AmountCaret extends StatelessWidget {
  const AmountCaret({super.key, required this.fontSize, required this.color});
  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) => _BlinkingCaret(fontSize: fontSize, color: color);
}

class _BlinkingCaret extends StatefulWidget {
  const _BlinkingCaret({required this.fontSize, required this.color});
  final double fontSize;
  final Color color;

  /// Height of Nunito's figures as a share of the font size (lining digits reach the cap height).
  static const double _figureHeight = 0.705;

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
        child: Transform.translate(
          // Measured on the Mac preview: this puts the caret's ends equally past the digits' top and baseline.
          offset: Offset(0, widget.fontSize * 0.24),
          child: Container(
            width: 3,
            height: widget.fontSize * (_BlinkingCaret._figureHeight + 0.18),
            decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1.5)),
          ),
        ),
      ),
    );
  }
}

/// In-app number pad modelled on Copilot's amount entry: 1–9, decimal point, 0, delete.
/// At most two decimals and one decimal point; long-press delete clears.
/// Lets a computer keyboard drive the amount while the on-screen [AmountKeypad] is up (the Mac
/// preview, or an iPad / iPhone with a keyboard attached): digits and the point type, + − * / (and
/// x) enter operators, Backspace deletes, Return saves. Nothing is taken while a text field (备注 …)
/// has focus or another sheet / picker sits on top, so typing there is untouched.
class AmountHardwareKeys extends StatefulWidget {
  const AmountHardwareKeys({
    super.key,
    required this.enabled,
    required this.text,
    required this.onChanged,
    required this.child,
    this.onLimit,
    this.onSubmit,
  });
  final bool enabled;
  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback? onLimit;

  /// Return / Enter; null when saving isn't possible yet.
  final VoidCallback? onSubmit;
  final Widget child;

  @override
  State<AmountHardwareKeys> createState() => _AmountHardwareKeysState();
}

class _AmountHardwareKeysState extends State<AmountHardwareKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  static const Map<String, String> _chars = {
    '.': '.', '。': '.', ',': '.',
    '+': '+', '-': '−', '−': '−', '*': '×', 'x': '×', 'X': '×', '×': '×', '/': '÷', '÷': '÷',
  };

  bool _onKey(KeyEvent event) {
    if (!mounted || !widget.enabled || event is KeyUpEvent) return false;
    // Only for this sheet, and not while typing into a text field.
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && (focused.widget is EditableText || focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
      _press('delete');
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) widget.onSubmit?.call();
      return true;
    }
    final character = event.character;
    if (character == null || character.isEmpty) return false;
    if (RegExp(r'^[0-9]$').hasMatch(character)) {
      _press(character);
      return true;
    }
    final mapped = _chars[character];
    if (mapped == null) return false;
    _press(mapped);
    return true;
  }

  void _press(String key) {
    final next = AmountKeypad.apply(widget.text, key);
    if (next == widget.text) {
      if (key != 'delete' && key != '.' && !AmountKeypad.operators.contains(key)) widget.onLimit?.call();
      return;
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.text, required this.onChanged, this.onLimit});
  final String text;
  final ValueChanged<String> onChanged;

  /// Called instead of [onChanged] when a digit or point is refused (length or precision limit).
  final VoidCallback? onLimit;

  /// The arithmetic keys: the amount may be a short calculation like "12.5+8×2", evaluated on save.
  static const operators = {'+', '−', '×', '÷'};

  static String apply(String text, String key) {
    if (key == 'delete') return text.isEmpty ? text : text.substring(0, text.length - 1);
    if (operators.contains(key)) {
      if (text.isEmpty) return text; // no leading operator
      // A second operator replaces the first; one after a dangling point drops the point.
      final last = text.substring(text.length - 1);
      final cut = operators.contains(last) || last == '.' ? text.length - 1 : text.length;
      return '${text.substring(0, cut)}$key';
    }
    // Digits and the point edit the operand after the last operator, not the whole text.
    final split = _lastOperatorSplit(text);
    final operand = text.substring(split);
    if (key == '.') {
      if (operand.contains('.')) return text;
      return operand.isEmpty ? '${text}0.' : '$text.';
    }
    final dot = operand.indexOf('.');
    if (dot >= 0) {
      return operand.length - dot - 1 >= 2 ? text : text + key;
    }
    if (operand.length >= 10) return text;
    if (operand == '0') return '${text.substring(0, split)}$key';
    return text + key;
  }

  /// Index just past the last operator; 0 while the text is one plain number.
  static int _lastOperatorSplit(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      if (operators.contains(text[i])) return i + 1;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const rows = [
      ['+', '1', '2', '3'],
      ['−', '4', '5', '6'],
      ['×', '7', '8', '9'],
      ['÷', '.', '0', 'delete'],
    ];
    Widget key(String value) {
      final flat = value == '.' || value == 'delete';
      // Operators read as function keys: a grey fill distinct from the white digit keys (the way
      // iOS's calculator separates its function column), and a narrower column so digits get the room.
      final operator = operators.contains(value);
      return Expanded(
        flex: operator ? 3 : 4,
        child: _KeypadKey(
          semanticLabel: value == 'delete' ? tr('删除，长按清空') : (value == '.' ? tr('小数点') : value),
          color: flat ? Colors.transparent : (operator ? p.ink.withValues(alpha: 0.07) : p.card),
          // Pressed: the key darkens like an iOS keyboard key (the flat keys gain a grey key shape).
          pressedColor: flat || operator ? p.ink.withValues(alpha: 0.16) : Color.lerp(p.card, p.ink, 0.12)!,
          onPress: () {
            final next = apply(text, value);
            if (next == text) {
              // Refused digit (limit hint), or a no-op: an extra point, or an operator with
              // nothing before it yet.
              if (value != 'delete' && value != '.' && !operators.contains(value)) {
                HapticFeedback.mediumImpact();
                onLimit?.call();
              }
              return;
            }
            onChanged(next);
          },
          onLongPress: value == 'delete'
              ? () {
                  HapticFeedback.mediumImpact();
                  onChanged('');
                }
              : null,
          child: value == 'delete'
              ? LIcon('delete', size: 22, color: p.ink, strokeWidth: 1.75)
              : Text(value, style: cw(25, weight: FontWeight.w400, color: p.ink)),
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

/// One key of [AmountKeypad], built to feel like the iOS keyboard: it acts the instant the finger
/// lands (not on lift, so fast typing never drops a key), with a light tap of the Taptic Engine and
/// the system keyboard click (which follows the phone's silent switch and keyboard-click setting).
/// The key turns darker at once and fades back after release, so even a quick tap visibly lands.
class _KeypadKey extends StatefulWidget {
  const _KeypadKey({
    required this.child,
    required this.color,
    required this.pressedColor,
    required this.onPress,
    this.onLongPress,
    this.semanticLabel,
  });
  final Widget child;
  final Color color;
  final Color pressedColor;
  final VoidCallback onPress;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<_KeypadKey> createState() => _KeypadKeyState();
}

class _KeypadKeyState extends State<_KeypadKey> {
  bool _down = false;

  void _press() {
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
    setState(() => _down = true);
    widget.onPress();
  }

  void _release() {
    if (_down && mounted) setState(() => _down = false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: widget.onLongPress,
        child: Listener(
          onPointerDown: (_) => _press(),
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: AnimatedContainer(
            // Darkens instantly on touch; eases back over 180 ms after release.
            duration: _down ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 48,
            decoration: BoxDecoration(color: _down ? widget.pressedColor : widget.color, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: AnimatedScale(
              // Shrinks at once under the finger; on release springs back with a slight overshoot.
              scale: _down ? 0.94 : 1,
              duration: _down ? const Duration(milliseconds: 60) : IOSMotion.bouncyCurve.duration,
              curve: _down ? Curves.easeOut : IOSMotion.bouncyCurve,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One category in a grid: the emoji on a plain disc with the name below. [checked] draws a black
/// ring and a small check; [badge] (e.g. a subcategory count) sits at the disc's top right.
/// Shared by 选择分类 and 设置 › 编辑分类 so both grids look the same.
class CategoryGridTile extends StatelessWidget {
  const CategoryGridTile({super.key, required this.name, required this.icon, required this.onTap, this.checked = false, this.badge});
  final String name;
  final Widget icon;
  final VoidCallback onTap;
  final bool checked;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      semanticLabel: name,
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 52,
          height: 52,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.card,
                shape: BoxShape.circle,
                border: Border.all(color: checked ? p.ink : Colors.transparent, width: 1.5),
              ),
              child: Center(child: icon),
            ),
            if (checked)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle, border: Border.all(color: p.canvas, width: 2)),
                  child: Center(child: LIcon('check', size: 10, color: p.onBrand, strokeWidth: 3.5)),
                ),
              )
            else if (badge != null)
              Positioned(
                right: -2,
                top: -1,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(color: p.muted, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.canvas, width: 2)),
                  child: Center(child: Text(badge!, style: cw(10, weight: FontWeight.w600, color: Colors.white, height: 1.0, spacing: 0))),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 5),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.footnote, color: p.muted)),
      ]),
    );
  }
}

/// Tiles in the adaptive grid both category sheets use: five per row on a full-width phone, four
/// or three as the sheet narrows.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 360 ? 5 : box.maxWidth >= 300 ? 4 : 3;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 10,
          crossAxisSpacing: 8,
          childAspectRatio: 0.95,
          children: children,
        );
      });
}

/// "选择分类" sheet for one kind. The first level is an adaptive five-per-row grid like the
/// editor's quick pick (four or three per row on narrow screens); a category with subcategories
/// opens them as a list. A 新增分类 button below the grid opens the editor, and categories are
/// read from the store live, so a just-added one appears immediately.
///
/// The one category picker used across the app (记一笔, 预算范围, 上级分类):
/// - [leadingLabel]: an extra first tile (全部支出 / 无) that pops '' and is checked when [selectedID] is ''.
/// - [parentSubtitle]: what a parent's own row says on the second level (默认 不细分; 预算用 含子分类).
/// - [topLevelOnly]: only the first level, every tile pops at once (上级分类).
/// - [excludeID]: a category left out (the one being edited can't be its own parent).
class CategoryChooser extends StatefulWidget {
  const CategoryChooser({
    super.key,
    required this.kind,
    required this.selectedID,
    this.title,
    this.leadingLabel,
    this.leadingIcon = 'layout-grid',
    this.parentSubtitle,
    this.topLevelOnly = false,
    this.excludeID,
    this.showAdd = true,
    this.initialParentID,
  });
  final EntryKind kind;
  final String selectedID;
  final String? title;
  final String? leadingLabel;
  final String leadingIcon;
  final String? parentSubtitle;
  final bool topLevelOnly;
  final String? excludeID;
  final bool showAdd;

  /// Open straight on this parent's subcategory list (from the editor's strip); 返回 then closes the
  /// sheet instead of going to the first level.
  final String? initialParentID;

  @override
  State<CategoryChooser> createState() => _CategoryChooserState();
}

class _CategoryChooserState extends State<CategoryChooser> {
  final TextEditingController _search = TextEditingController();

  /// The top-level category whose subcategories are showing; null = the first level.
  LedgerCategory? _parent;

  /// +1 when going into a parent, −1 when coming back: which way the list slides, like a push.
  int _direction = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LedgerCategory> _all(LedgerStore store) => store.ledger.categories
      .where((c) => c.kind == widget.kind && c.id != widget.excludeID && (!widget.topLevelOnly || _isTop(store, c)))
      .toList();

  /// A first-level category, or one whose parent no longer exists (shown as first level too).
  bool _isTop(LedgerStore store, LedgerCategory c) => c.parentID == null || _byID(store, c.parentID) == null;

  /// Top-level categories in display order: the ledger's own category list order.
  List<LedgerCategory> _tops(LedgerStore store) => _all(store).where((c) => _isTop(store, c)).toList();

  List<LedgerCategory> _childrenOf(LedgerStore store, String id) => store.ledger.categories.where((c) => c.parentID == id).toList();

  LedgerCategory? _byID(LedgerStore store, String? id) => id == null ? null : store.ledger.categories.where((c) => c.id == id).firstOrNull;

  void _open(LedgerCategory parent) {
    HapticFeedback.selectionClick();
    setState(() {
      _direction = 1;
      _parent = parent;
    });
  }

  bool _placed = false;

  /// Opened directly on a parent's list and still showing it: back leaves the sheet.
  bool get _backCloses => widget.initialParentID != null && _parent?.id == widget.initialParentID;

  void _back() {
    if (_backCloses) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _direction = -1;
      _parent = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    if (!_placed) {
      _placed = true;
      _parent = _byID(store, widget.initialParentID);
    }
    final query = _search.text.trim().toLowerCase();
    final selected = _byID(store, widget.selectedID);
    final selectedTop = selected?.parentID ?? selected?.id;

    Widget row(LedgerCategory c, {String? title, String? subtitle, bool chevron = false, bool checked = false, VoidCallback? onTap}) => Pressable(
          semanticLabel: title ?? c.name,
          onTap: onTap ?? () => Navigator.of(context).pop(c.id),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(children: [
              CategoryIcon(c, size: 20, color: categoryTint(c.id)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title ?? c.name, style: cw(IOSText.body, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null) Text(subtitle, style: cw(IOSText.footnote, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (checked) ...[LIcon('check', size: 17, color: p.accent, strokeWidth: 2.5), const SizedBox(width: 6)],
              if (chevron) LIcon('chevron-right', size: 14, color: p.muted.withValues(alpha: 0.6)),
            ]),
          ),
        );

    // A quick-pick tile like the editor's: the emoji on a plain disc; a selected one gets a black
    // ring and a small check.
    Widget discTile({required String name, required Widget icon, required bool checked, required VoidCallback onTap}) =>
        CategoryGridTile(name: name, icon: icon, checked: checked, onTap: onTap);

    Widget tile(LedgerCategory c) {
      final hasChildren = !widget.topLevelOnly && _childrenOf(store, c.id).isNotEmpty;
      return discTile(
        name: c.name,
        icon: CategoryIcon(c, size: 24, color: categoryTint(c.id)),
        checked: selectedTop == c.id,
        onTap: hasChildren ? () => _open(c) : () => Navigator.of(context).pop(c.id),
      );
    }

    // The extra first tile (全部支出 / 无): pops ''.
    Widget allTile() => discTile(
          name: widget.leadingLabel!,
          icon: LIcon(widget.leadingIcon, size: 22, color: p.ink),
          checked: widget.selectedID.isEmpty,
          onTap: () => Navigator.of(context).pop(''),
        );

    final searchRow = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        LIcon('search', size: 17, color: p.muted),
        const SizedBox(width: 8),
        Expanded(child: FormTextField(controller: _search, hint: tr('搜索分类'), onChanged: (_) => setState(() => _direction = 0))),
      ]),
    );

    final List<Widget>? rows;
    if (query.isNotEmpty) {
      // Searching: every match from both levels, subcategories shown with their parent's name.
      rows = [
        for (final c in _all(store).where((c) => c.name.toLowerCase().contains(query)))
          row(c, title: c.parentID == null ? c.name : '${_byID(store, c.parentID)?.name ?? ''} › ${c.name}', checked: c.id == widget.selectedID),
      ];
    } else if (_parent == null) {
      rows = null; // first level: the grid
    } else {
      // Second level: the parent itself first ("不细分"), then its subcategories.
      final parent = _parent!;
      rows = [
        row(parent, subtitle: widget.parentSubtitle ?? tr('不细分'), checked: widget.selectedID == parent.id),
        for (final c in _childrenOf(store, parent.id)) row(c, checked: c.id == widget.selectedID),
      ];
    }

    final Widget content;
    if (rows != null) {
      content = CwCard(
        key: ValueKey(query.isNotEmpty ? 'search' : 'sub-${_parent!.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Padding(padding: const EdgeInsets.only(left: 35), child: Divider(height: 0.5, thickness: 0.5, color: p.cardStroke)),
            rows[i],
          ],
          if (rows.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(tr('没有匹配的分类'), style: cw(IOSText.subheadline, color: p.muted))),
        ]),
      );
    } else {
      // Adaptive density: five per row on a full-width phone, four or three as the sheet gets
      // narrower, so the emoji discs and names never crowd.
      content = Column(key: const ValueKey('top'), children: [
        CategoryGrid(key: const ValueKey('grid'), children: [if (widget.leadingLabel != null) allTile(), for (final c in _tops(store)) tile(c)]),
        if (widget.showAdd) ...[
        const SizedBox(height: 14),
        Center(
          child: Pressable(
            semanticLabel: tr('新增分类'),
            onTap: () => showCwSheet<void>(context, (_) => StoreScope(store: store, child: CategoryEditor(initialKind: widget.kind))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.cardStroke, width: 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LIcon('plus', size: 15, color: p.ink),
                const SizedBox(width: 6),
                Text(tr('新增分类'), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.ink)),
              ]),
            ),
          ),
        ),
        ],
      ]);
    }

    return PopScope(
      // While a subcategory list is open, the back gesture / Esc returns to the first level.
      canPop: _parent == null || _backCloses,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SheetScaffold(
        title: _parent?.name ?? widget.title ?? tr('选择分类'),
        leadingLabel: _parent == null ? null : tr('返回'),
        onLeading: _parent == null ? null : _back,
        // The search field stays put; below it the grid, a subcategory list and search results
        // change with an iOS push (search: a cross-fade). Each level scrolls on its own.
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 14), child: searchRow),
          Expanded(
            child: PushSwitcher(
              direction: _direction,
              child: ListView(
                key: content.key,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [KeyedSubtree(child: content)],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

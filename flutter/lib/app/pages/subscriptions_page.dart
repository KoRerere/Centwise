import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../components.dart';
import '../entry_editor.dart' show AmountCaret, AmountHardwareKeys, AmountKeypad, CategoryChooser, CategoryGridTile;
import '../motion.dart';
import '../icons.dart';
import '../sheets.dart';
import '../store.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import 'dashboard_page.dart' show PageList;

/// Opens the subscription editor: a new subscription, or [subscription] to edit / cancel / resume.
void openSubscription(BuildContext context, [Subscription? subscription]) {
  final store = StoreScope.read(context);
  showCwSheet<void>(context, (_) => StoreScope(store: store, child: SubscriptionEditor(subscription: subscription)), guarded: true);
}

/// "11月3日" this year, "2027年1月3日" otherwise; 今天 / 明天 / 昨天 close by.
String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = DateTime(day.year, day.month, day.day).difference(today).inDays;
  if (difference == 0) return tr('今天');
  if (difference == 1) return tr('明天');
  if (difference == -1) return tr('昨天');
  return day.year == now.year ? fmtMonthDay(day) : fmtYMD(day);
}

/// Asks before booking the due charge: 记一笔支出 (confirm) or 跳过本期. Returns after the store acted.
Future<void> confirmSubscriptionCharge(BuildContext context, Subscription s) async {
  final store = StoreScope.read(context);
  final category = s.categoryID == null ? null : store.category(s.categoryID!);
  final choice = await showIOSAlert<String>(
    context,
    title: tr('确认 {name} 的扣费？', {'name': s.name}),
    message: tr('将记一笔 {amount} 的支出（{category}），日期为 {date}。同一期只会记一次。', {
      'amount': Money.text(s.amount),
      'category': category?.name ?? tr('其他'),
      'date': fmtMonthDay(s.nextDate),
    }),
    actions: [
      IOSAlertAction(label: tr('记一笔支出'), value: 'confirm', prominent: true),
      IOSAlertAction(label: tr('跳过本期'), value: 'skip'),
      IOSAlertAction(label: tr('取消'), value: 'cancel'),
    ],
  );
  if (choice == 'confirm') {
    tick();
    store.confirmSubscriptionCharge(s.id);
  } else if (choice == 'skip') {
    store.skipSubscriptionCharge(s.id);
  }
}

/// 订阅: the running costs at a glance (how many, the monthly average, what this month will charge),
/// then the subscriptions in charge-date order, switchable between 订阅中 and 已取消.
class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  bool _showCancelled = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    final active = ledger.activeSubscriptions..sort((a, b) {
        final byDate = a.nextDate.compareTo(b.nextDate);
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });
    final cancelled = [for (final s in ledger.subscriptions) if (s.cancelled) s]
      ..sort((a, b) => (b.cancelledAt ?? DateTime(1970)).compareTo(a.cancelledAt ?? DateTime(1970)));
    final list = _showCancelled ? cancelled : active;
    final now = DateTime.now();

    return PageList(children: [
      _SummaryCard(
        count: active.length,
        monthlyAverage: ledger.subscriptionMonthlyAverage,
        thisMonth: ledger.subscriptionChargesIn(now),
        due: active.where((s) => s.isDue(now)).length,
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CapsuleSegments<bool>(
          values: const [false, true],
          selected: _showCancelled,
          label: (v) => v ? tr('已取消 {n}', {'n': cancelled.length}) : tr('订阅中 {n}', {'n': active.length}),
          onChanged: (v) => setState(() => _showCancelled = v),
        ),
        const SizedBox(height: 14),
        if (list.isEmpty)
          CwCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: EmptyState(
              icon: 'refresh-cw',
              title: _showCancelled ? tr('没有已取消的订阅') : tr('还没有订阅'),
              message: _showCancelled ? tr('取消的订阅会留在这里，历史账单不受影响。') : tr('那些每月悄悄溜走的钱，都请到这儿排排坐。'),
              actionLabel: _showCancelled ? null : tr('添加固定扣费项'),
              onAction: _showCancelled ? null : () => openSubscription(context),
            ),
          )
        else
          CwCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: BillIcon.textInset),
                    child: Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
                  ),
                _SubscriptionRow(subscription: list[i]),
              ],
            ]),
          ),
      ]),
    ]);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.count, required this.monthlyAverage, required this.thisMonth, required this.due});
  final int count;
  final int monthlyAverage;
  final int thisMonth;
  final int due;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget stat(String label, Widget value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: cw(IOSText.footnote, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            value,
          ]),
        );
    return CwCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('月均固定费用'), style: cw(IOSText.footnote, color: p.muted)),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft, child: AmountText(monthlyAverage, size: 34, weight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 14),
        Row(children: [
          stat(tr('订阅中'), Text(tr('{n} 个', {'n': count}), style: cw(20, weight: FontWeight.w700, color: p.ink, brand: true))),
          stat(
            tr('本月预计扣费'),
            Align(alignment: Alignment.centerLeft, child: AmountText(thisMonth, size: 20, weight: FontWeight.w700, color: p.ink)),
          ),
        ]),
        // Only a reminder when something is waiting to be confirmed; otherwise no footnote.
        if (due > 0) ...[
          const SizedBox(height: 12),
          Text(tr('{n} 笔扣费待确认，确认后才会记入支出。', {'n': due}), style: cw(IOSText.footnote, color: p.warning)),
        ],
      ]),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({required this.subscription});
  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final s = subscription;
    final category = s.categoryID == null ? null : store.category(s.categoryID!);
    final due = s.isDue(DateTime.now());
    final String detail;
    if (s.cancelled) {
      detail = s.cancelledAt == null
          ? '${s.cycle.title} · ${tr('已取消')}'
          : '${s.cycle.title} · ${tr('{date}取消', {'date': _dayLabel(s.cancelledAt!)})}';
    } else if (due) {
      detail = tr('待确认 · {date}应扣', {'date': _dayLabel(s.nextDate)});
    } else {
      detail = '${s.cycle.title} · ${tr('{date}扣费', {'date': _dayLabel(s.nextDate)})}';
    }
    return Pressable(
      onTap: () => openSubscription(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          Opacity(
            opacity: s.cancelled ? 0.5 : 1,
            child: BillIcon(
              child: category != null
                  ? CategoryIcon(category, size: 24, color: categoryTint(category.id))
                  : LIcon('refresh-cw', size: 19, color: p.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name,
                  style: cw(IOSText.body, color: s.cancelled ? p.muted : p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(detail,
                  style: cw(14, weight: due ? FontWeight.w600 : FontWeight.w400, color: due ? p.warning : p.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            AmountText(s.amount, size: IOSText.body, weight: FontWeight.w600, color: s.cancelled ? p.muted : p.ink, brand: false),
            if (due) ...[
              const SizedBox(height: 4),
              Pressable(
                semanticLabel: tr('确认扣费'),
                pressScale: 0.94,
                onTap: () => confirmSubscriptionCharge(context, s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(99)),
                  child: Text(tr('确认'), style: cw(13, weight: FontWeight.w600, color: p.onBrand)),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// 新增订阅 / 编辑订阅, laid out like 记一笔: the amount up top with the same number pad, then the
/// category strip, name and note cards, and at the bottom the 月付 / 季付 / 年付 switch, the next
/// charge day and a full-width save button. An existing subscription also gets its actions
/// (confirm a due charge, mark cancelled, start again) in a card below the form.
class SubscriptionEditor extends StatefulWidget {
  const SubscriptionEditor({super.key, this.subscription});
  final Subscription? subscription;

  @override
  State<SubscriptionEditor> createState() => _SubscriptionEditorState();
}

class _SubscriptionEditorState extends State<SubscriptionEditor> {
  Subscription? get original => widget.subscription;

  late String _amount = original == null ? '' : Money.input(original!.amount);
  late final TextEditingController _name = TextEditingController(text: original?.name ?? '');
  late final TextEditingController _note = TextEditingController(text: original?.note ?? '');
  late BillingCycle _cycle = original?.cycle ?? BillingCycle.monthly;
  late DateTime _nextDate = original?.nextDate ?? _today();
  late String? _categoryID = original?.categoryID;
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();
  final PageController _categoryPages = PageController();
  int _categoryPage = 0;

  /// The number pad is up for a new subscription, like 记一笔.
  late bool _keypadVisible = original == null;

  /// What the form held when it opened, to tell whether closing would throw changes away.
  late final String _initial;

  @override
  void initState() {
    super.initState();
    _initial = _snapshot();
    // A text field gaining or losing focus changes the list's bottom room (see the ListView).
    for (final node in [_nameFocus, _noteFocus]) {
      node.addListener(() {
        if (mounted) setState(() {});
      });
    }
    for (final node in [_nameFocus, _noteFocus]) {
      node.addListener(() {
        if (node.hasFocus && _keypadVisible) _hideKeypad();
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _nameFocus.dispose();
    _noteFocus.dispose();
    _categoryPages.dispose();
    super.dispose();
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _snapshot() => [_name.text, _amount, _note.text, _cycle.name, dayKey(_nextDate), _categoryID ?? ''].join('\u0001');

  int? get _cents {
    try {
      return Money.parse(_amount);
    } on LedgerError {
      return null;
    }
  }

  /// Puts the number pad away; a typed calculation ("25+12") becomes its result.
  void _hideKeypad() {
    setState(() {
      _keypadVisible = false;
      if (_amount.contains(RegExp(r'[+−×÷]'))) {
        final cents = _cents;
        if (cents != null) _amount = Money.input(cents);
      }
    });
  }

  bool get _canSave => _name.text.trim().isNotEmpty && (_cents ?? 0) > 0;

  void _save() {
    final store = StoreScope.read(context);
    try {
      final name = _name.text.trim();
      if (name.isEmpty) throw LedgerError(tr('请填写订阅名称。'));
      final amount = Money.parse(_amount);
      if (amount <= 0) throw LedgerError(tr('每次扣费金额需要大于零。'));
      final old = original;
      // A changed charge day becomes the new day of the month it bills on.
      final dateChanged = old == null || dayKey(old.nextDate) != dayKey(_nextDate);
      final subscription = Subscription(
        id: old?.id,
        name: name,
        amount: amount,
        cycle: _cycle,
        nextDate: _nextDate,
        categoryID: _categoryID,
        note: _note.text.trim(),
        cancelled: old?.cancelled ?? false,
        cancelledAt: old?.cancelledAt,
        anchorDay: dateChanged ? _nextDate.day : old.anchorDay,
        charged: old == null ? null : List.of(old.charged),
      );
      if (store.saveSubscription(subscription)) Navigator.of(context).pop();
    } on LedgerError catch (e) {
      showCwAlert(context, tr('请检查输入'), e.message);
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    var picked = _nextDate;
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
                  picked = _today();
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
                minimumDate: DateTime(2000, 1, 1),
                maximumDate: DateTime(2099, 12, 31),
                onDateTimeChanged: (value) => picked = DateTime(value.year, value.month, value.day),
              ),
            ),
          ]),
        ),
      ),
    );
    if (mounted) setState(() => _nextDate = picked);
  }

  /// The full picker, or (from a strip tile with subcategories) straight into that parent's list.
  Future<void> _chooseCategory({String? parentID}) async {
    final store = StoreScope.read(context);
    FocusScope.of(context).unfocus();
    double? height;
    if (parentID != null) {
      final children = store.ledger.categories.where((c) => c.parentID == parentID).length;
      height = 140 + 60 + children * 51.0 + 40 + MediaQuery.paddingOf(context).bottom;
    }
    final id = await showCwSheet<String>(
      context,
      (_) => StoreScope(
        store: store,
        child: CategoryChooser(kind: EntryKind.expense, selectedID: _categoryID ?? '', initialParentID: parentID),
      ),
      height: height,
    );
    if (id != null && mounted) setState(() => _categoryID = id.isEmpty ? null : id);
  }

  Future<void> _cancel() async {
    final store = StoreScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmDestructive(context, tr('标记为已取消后不再提醒扣费，已记的历史账单会保留。'), tr('标记为已取消'));
    if (ok && store.cancelSubscription(original!.id)) navigator.pop();
  }

  Future<void> _confirmDue() async {
    final navigator = Navigator.of(context);
    final store = StoreScope.read(context);
    await confirmSubscriptionCharge(context, original!);
    final now = store.ledger.subscriptions.where((s) => s.id == original!.id).firstOrNullValue;
    if (now != null && !now.isDue(DateTime.now()) && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final s = original;
    final live = s == null ? null : store.ledger.subscriptions.where((x) => x.id == s.id).firstOrNullValue;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_snapshot() == _initial || await confirmDiscardChanges(context)) navigator.pop();
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: GestureDetector(
          // A tap on a blank part of the form puts both keyboards away, as in 记一笔.
          onTap: () {
            FocusScope.of(context).unfocus();
            if (_keypadVisible) _hideKeypad();
          },
          behavior: HitTestBehavior.translucent,
          child: AmountHardwareKeys(
            enabled: _keypadVisible,
            text: _amount,
            onChanged: (v) => setState(() => _amount = v),
            onSubmit: _canSave ? _save : null,
            child: SheetScaffold(
            title: s == null ? tr('新增订阅') : tr('编辑订阅'),
            titleWidget: const SizedBox.shrink(),
            contentUnderBar: true,
            body: ListView(
              clipBehavior: Clip.none,
              // Bottom room = the controls floating over the form: the type / date bar and save button
          // (~150), plus the number pad while it is up, so the note can always be scrolled up
          // above the pad and tapped (which brings up the system keyboard).
          // While a text field is being typed in, extra room lets it scroll up above the save bar,
          // so what's being typed stays in view over the system keyboard; it goes away afterwards.
          padding: EdgeInsets.fromLTRB(18, 34, 18,
              150 + (_keypadVisible ? 246 + MediaQuery.paddingOf(context).bottom : 0) + (_nameFocus.hasFocus || _noteFocus.hasFocus ? 220 : 0)),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _amountDisplay(p),
                const SizedBox(height: 14),
                _categorySection(store, p),
                const SizedBox(height: 18),
                CwCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(children: [
                    _textRow(p, 'tag', _name, _nameFocus, tr('订阅名称')),
                    Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
                    _textRow(p, 'file-text', _note, _noteFocus, tr('添加备注')),
                  ]),
                ),
                if (live != null) ...[
                  const SizedBox(height: 18),
                  _actions(live, p),
                ],
              ],
            ),
            bottom: _bottom(p),
          ),
          ),
        ),
      ),
    );
  }

  static String _grouped(String text) {
    final out = StringBuffer();
    for (final part in RegExp(r'[0-9.]+|[^0-9.]+').allMatches(text)) {
      final token = part.group(0)!;
      if (!token.contains(RegExp('[0-9]'))) {
        out.write(token);
        continue;
      }
      final dot = token.indexOf('.');
      final whole = dot < 0 ? token : token.substring(0, dot);
      for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
        out.write(whole[i]);
      }
      if (dot >= 0) out.write(token.substring(dot));
    }
    return out.toString();
  }

  Widget _amountDisplay(Palette p) {
    final large = _amount.length <= 9;
    final monthly = switch (_cycle) {
      BillingCycle.monthly => null,
      BillingCycle.quarterly => (_cents ?? 0) > 0 ? tr('约每月 {amount}', {'amount': Money.text((_cents! / 3).round())}) : null,
      BillingCycle.yearly => (_cents ?? 0) > 0 ? tr('约每月 {amount}', {'amount': Money.text((_cents! / 12).round())}) : null,
    };
    return Column(children: [
      Text(tr('每次扣费'), style: cw(IOSText.footnote, color: p.muted)),
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
                Text(Money.symbol, style: cw(24, weight: FontWeight.w700, color: p.ink, brand: true)),
                const SizedBox(width: 2),
                Text(_amount.isEmpty ? '0' : _grouped(_amount),
                    style: cw(large ? 54 : 38, weight: FontWeight.w700, color: _amount.isEmpty ? p.muted.withValues(alpha: 0.6) : p.ink, brand: true)),
                if (_keypadVisible) ...[const SizedBox(width: 3), AmountCaret(fontSize: large ? 54 : 38, color: p.ink)],
              ],
            ),
          ),
        ),
      ),
      if (monthly != null) Text(monthly, style: cw(IOSText.footnote, color: p.muted)),
    ]);
  }

  /// First-level expense categories in pages of ten, like 记一笔's strip; one with subcategories opens
  /// its list. The chosen subcategory's name shows under its parent.
  Widget _categorySection(LedgerStore store, Palette p) {
    final ledger = store.ledger;
    final tops = [
      for (final c in ledger.categories)
        if (c.kind == EntryKind.expense && (c.parentID == null || ledger.categoryByID(c.parentID!) == null)) c
    ];
    final chosen = _categoryID == null ? null : ledger.categoryByID(_categoryID!);
    final pages = (tops.length / 10).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(tr('分类'), trailing: tr('全部分类'), onTap: () => _chooseCategory()),
      const SizedBox(height: 12),
      SizedBox(
        height: 164,
        child: LayoutBuilder(builder: (context, constraints) {
          final width = (constraints.maxWidth - 4 * 8) / 5;
          Widget tile(LedgerCategory c) {
            final selected = chosen != null && (chosen.id == c.id || chosen.parentID == c.id);
            final opensList = ledger.categories.any((x) => x.parentID == c.id);
            return SelectPop(
              selected: selected,
              child: CategoryGridTile(
                name: selected && chosen.id != c.id ? chosen.name : c.name,
                icon: CategoryIcon(c, size: 24, color: categoryTint(c.id)),
                checked: selected,
                onTap: opensList
                    ? () => _chooseCategory(parentID: c.id)
                    : () => setState(() => _categoryID = selected ? null : c.id),
              ),
            );
          }

          return PageView.builder(
            controller: _categoryPages,
            itemCount: pages,
            onPageChanged: (i) => setState(() => _categoryPage = i),
            itemBuilder: (context, page) => Column(children: [
              for (final r in const [0, 5])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var c = 0; c < 5; c++) ...[
                      if (c > 0) const SizedBox(width: 8),
                      SizedBox(
                        width: width,
                        height: 76,
                        child: page * 10 + r + c < tops.length ? tile(tops[page * 10 + r + c]) : null,
                      ),
                    ],
                  ]),
                ),
            ]),
          );
        }),
      ),
      if (pages > 1) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < pages; i++)
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

  /// An icon and a 17 pt field on a 52 pt row, like 记一笔's note row.
  Widget _textRow(Palette p, String icon, TextEditingController controller, FocusNode focus, String hint) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(children: [
          LIcon(icon, size: 20, color: p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              scrollPadding: const EdgeInsets.only(bottom: 220),
              onChanged: (_) => setState(() {}),
              style: cw(IOSText.body, color: p.ink),
              cursorColor: p.ink,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                hintText: hint,
                hintStyle: cw(IOSText.body, color: p.muted),
              ),
            ),
          ),
        ]),
      );

  /// Confirm a due charge / mark cancelled / start again, as one card like 记一笔's 删除 row.
  Widget _actions(Subscription live, Palette p) {
    Widget row(String icon, String label, Color color, VoidCallback onTap) => Pressable(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              LIcon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Text(label, style: cw(IOSText.body, weight: FontWeight.w500, color: color)),
            ]),
          ),
        );
    final due = !live.cancelled && live.isDue(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          if (due) ...[
            row('check', tr('确认 {date} 的扣费', {'date': fmtMonthDay(live.nextDate)}), p.ink, _confirmDue),
            Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
          ],
          if (live.cancelled)
            row('undo-2', tr('重新订阅'), p.ink, () {
              if (StoreScope.read(context).resumeSubscription(live.id)) Navigator.of(context).pop();
            })
          else
            row('circle-x', tr('标记为已取消'), p.over, _cancel),
        ]),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          [
            live.cancelled
                ? tr('重新订阅后从下一个扣费日继续，取消期间的扣费不会补记。')
                : tr('到期后显示“待确认”，确认才会生成一笔支出；同一期只会记一次。'),
            if (live.charged.isNotEmpty) tr('已记账 {n} 期，最近一次 {date}。', {'n': live.charged.length, 'date': _lastCharged(live)}),
          ].join(' '),
          style: cw(IOSText.footnote, color: p.muted),
        ),
      ),
    ]);
  }

  /// [月付|季付|年付] on the left, the next charge day on the right, then 保存订阅 and the number pad —
  /// on a frosted backdrop the form scrolls behind, as in 记一笔.
  Widget _bottom(Palette p) {
    final content = Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, _keypadVisible ? 10 : 14 + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 34,
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 64.0 * BillingCycle.values.length,
                      child: CapsuleSegments<BillingCycle>(
                        values: BillingCycle.values,
                        selected: _cycle,
                        label: (c) => c.title,
                        onChanged: (c) => setState(() => _cycle = c),
                        height: 34,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Pressable(
                semanticLabel: tr('下次扣费日期 {date}，轻点修改', {'date': fmtYMD(_nextDate)}),
                onTap: _pickDate,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  LIcon('calendar', size: 15, color: p.muted),
                  const SizedBox(width: 5),
                  Text(tr('{date}扣费', {'date': _dayLabel(_nextDate)}), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.ink)),
                  const SizedBox(width: 2),
                  LIcon('chevron-down', size: 14, color: p.muted),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          PrimaryBarButton(label: tr('保存订阅'), tint: p.brand, onTap: _canSave ? _save : null),
        ]),
      ),
      AnimatedSize(
        duration: IOSMotion.smoothCurve.duration,
        curve: IOSMotion.smoothCurve,
        child: _keypadVisible
            ? AmountKeypad(text: _amount, onChanged: (v) => setState(() => _amount = v))
            : const SizedBox(width: double.infinity),
      ),
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Stack(clipBehavior: Clip.none, children: [
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
        Positioned(
          left: 0,
          right: 0,
          top: -46,
          height: 46,
          child: IgnorePointer(
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
        ),
      ]),
    );
  }

  static String _lastCharged(Subscription s) {
    final keys = List.of(s.charged)..sort();
    final parts = keys.last.split('-').map(int.parse).toList();
    return _dayLabel(DateTime(parts[0], parts[1], parts[2]));
  }
}

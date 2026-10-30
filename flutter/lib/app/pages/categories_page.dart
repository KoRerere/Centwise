import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../charts.dart';
import '../components.dart';
import '../entry_editor.dart' show CategoryChooser;
import '../icons.dart';
import '../sheets.dart';
import '../store.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import 'dashboard_page.dart' show PageList;
import 'transactions_page.dart';

/// Copilot "Categories": donut summary, spent-vs-budget rows, total budget, six-month trend.
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  void _openBudget(BuildContext context, {Budget? budget, String? categoryID}) {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: BudgetEditor(budget: budget, categoryID: categoryID)));
  }

  /// One category's bills for the selected period, reusing the bill page.
  void _openCategory(BuildContext context, LedgerCategory category, {bool includeSubcategories = true, String? title}) {
    final store = StoreScope.read(context);
    showCwSheet<void>(
      context,
      (_) => StoreScope(
        store: store,
        child: SheetScaffold(
          title: title ?? category.name,
          leadingLabel: tr('完成'),
          body: TransactionsPage(categoryID: category.id, includeSubcategories: includeSubcategories),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    // Donut and rows both follow the period chosen in the bottom capsule; budgets are monthly and have
    // their own card below, labelled with the month.
    final spending = store.periodCategorySpending;
    final monthBudgets = ledger.budgetsFor(store.month);

    final spentByID = {for (final (c, v) in spending) c.id: v};
    final budgetByID = <String, Budget>{
      for (final b in monthBudgets)
        if (b.categoryID != null) b.categoryID!: b
    };
    // Two levels, like Money Pro: each top-level category shows the total of its subcategories, and
    // expands to list them. Budgets are monthly, so bars always show progress for the whole month.
    int subtreeSpent(String id) => ledger.subtreeIDs(id).fold(0, (s, x) => s + (spentByID[x] ?? 0));
    _CategoryLine line(LedgerCategory category, int spent, {bool directOnly = false}) {
      final budget = directOnly ? null : budgetByID[category.id];
      final monthSpent = budget == null ? 0 : ledger.spent(budget, store.month);
      return _CategoryLine(category, spent, budget, monthSpent, directOnly: directOnly);
    }

    int byAmount(_CategoryLine a, _CategoryLine b) =>
        a.spent == b.spent ? a.category.name.compareTo(b.category.name) : b.spent.compareTo(a.spent);
    final groups = <_CategoryGroup>[];
    final topLevel = ledger.categories
        .where((c) => c.kind == EntryKind.expense && (c.parentID == null || ledger.categoryByID(c.parentID!) == null));
    for (final top in topLevel) {
      final children = <_CategoryLine>[
        for (final child in ledger.childrenOf(top.id))
          if (subtreeSpent(child.id) != 0 || budgetByID.containsKey(child.id)) line(child, subtreeSpent(child.id)),
      ]..sort(byAmount);
      final direct = spentByID[top.id] ?? 0;
      // Bills filed on the parent itself, when it also has subcategories listed.
      if (children.isNotEmpty && direct != 0) children.add(line(top, direct, directOnly: true));
      final head = line(top, subtreeSpent(top.id));
      if (head.spent == 0 && head.budget == null && children.isEmpty) continue;
      groups.add(_CategoryGroup(head, children));
    }
    groups.sort((a, b) => byAmount(a.head, b.head));
    final emptyText = switch (store.period) { Period.day => tr('这一天还没有支出'), Period.month => tr('本月还没有支出'), Period.year => tr('近一年还没有支出') };

    // Colours by rank this period (largest first), so neighbouring slices and dots never share a colour.
    final topSpending = ledger.topLevelSpendingIn(store.entriesIn(store.interval));
    final tints = <String, Color>{
      for (var i = 0; i < topSpending.length; i++) topSpending[i].$1.id: categoryPalette[i % categoryPalette.length],
    };
    final trendMonths = [for (var offset = -5; offset <= 0; offset++) DateTime(store.month.year, store.month.month + offset, 1)];

    return PageList(children: [
      _PeriodSummary(spending: topSpending, tints: tints, emptyText: emptyText),
      // Rows. With nothing to list the summary card above already shows the empty state, and the
      // whole block is left out (an empty block would still take a PageList gap, doubling the space).
      if (groups.isNotEmpty)
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CwCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          child: _CategoryGrid(
                  groups: groups,
                  tints: tints,
                  onOpen: (line) => _openCategory(context, line.category,
                      includeSubcategories: !line.directOnly,
                      title: line.directOnly ? tr('{name} · 未细分', {'name': line.category.name}) : null),
                  onBudget: (line) => _openBudget(context, budget: line.budget, categoryID: line.category.id),
                ),
        ),
        // Each category row has its own 设预算; the total budget has its own card below.
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Spacer(),
            // For a category that isn't listed yet (no spending this period).
            Pressable(
              onTap: () => _openBudget(context, categoryID: groups.first.head.category.id),
              child: Row(children: [
                LIcon('plus', size: 14, color: p.accent, strokeWidth: 2.5),
                const SizedBox(width: 3),
                Text(tr('分类预算'), style: cw(IOSText.footnote, weight: FontWeight.w600, color: p.accent)),
              ]),
            ),
          ]),
        ],
      ]),
      const _MonthBudgetCard(),
      // Six-month trend
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardCaption(tr('近六个月')),
        const SizedBox(height: 10),
        CwCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TrendChart(
              labels: [for (final m in trendMonths) fmtMonth(m)],
              titles: [for (final m in trendMonths) fmtYearMonth(m)],
              income: [for (final m in trendMonths) ledger.total(EntryKind.income, m)],
              expense: [for (final m in trendMonths) ledger.total(EntryKind.expense, m)],
            ),
          ]),
        ),
      ]),
    ]);
  }
}

/// One row of the category table: a category, what it spent in the period, and its monthly budget.
class _CategoryLine {
  _CategoryLine(this.category, this.spent, this.budget, this.monthSpent, {this.directOnly = false});
  final LedgerCategory category;
  final int spent;
  final Budget? budget;
  final int monthSpent;

  /// The "未细分" row: bills filed on a parent category itself rather than one of its subcategories.
  final bool directOnly;
}

class _CategoryGroup {
  _CategoryGroup(this.head, this.children);
  final _CategoryLine head;
  final List<_CategoryLine> children;
}

/// The period's category spending as a five-per-row tile grid: emoji disc, name and the amount, in
/// rank order. Tap opens the category's bills (subcategories included); a long press sets its budget.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.groups, required this.tints, required this.onOpen, required this.onBudget});
  final List<_CategoryGroup> groups;
  final Map<String, Color> tints;
  final void Function(_CategoryLine) onOpen;
  final void Function(_CategoryLine) onBudget;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lines = [for (final g in groups) g.head];
    return GridView.count(
      crossAxisCount: 5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      mainAxisSpacing: 8,
      crossAxisSpacing: 6,
      mainAxisExtent: 104,
      children: [
        for (final line in lines)
          Pressable(
            semanticLabel: line.category.name,
            onTap: () => onOpen(line),
            onLongPress: () => onBudget(line),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: p.canvas, shape: BoxShape.circle),
                child: Center(child: CategoryIcon(line.category, size: 26)),
              ),
              const SizedBox(height: 5),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: tints[line.category.id] ?? p.muted, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(line.category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cw(12, weight: FontWeight.w500, color: p.ink))),
              ]),
              const SizedBox(height: 2),
              AmountText(line.spent, size: 12, weight: FontWeight.w600, color: p.ink),
            ]),
          ),
      ],
    );
  }
}
/// Spending in the selected period by category: donut, total and the three largest shares.
class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.spending, required this.tints, required this.emptyText});
  final List<(LedgerCategory, int)> spending;
  final Map<String, Color> tints;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final slices = [for (final (c, v) in spending) if (v > 0) (c, v)]..sort((a, b) => b.$2.compareTo(a.$2));
    final total = slices.fold<int>(0, (s, e) => s + e.$2);
    if (total <= 0) {
      // No spending in this period: say so instead of drawing an empty ring.
      return CwCard(
        // The dotted empty state fills the whole card.
        padding: EdgeInsets.zero,
        child: Center(
          child: EmptyState(icon: 'piggy-bank', illustration: 'wallet', title: emptyText, message: tr('有支出后，这里会按分类显示占比')),
        ),
      );
    }
    String percent(int v) {
      final value = v * 100 / total;
      return value < 1 ? '<1%' : '${value.round()}%';
    }

    // 今日 / 本月 / 近一年 while following now; the specific day or month when browsing back.
    final periodLabel = store.isCurrentPeriod ? store.periodWord : store.periodName;
    return CwCard(
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        Semantics(
          label: tr('{period}支出分类占比', {'period': periodLabel}),
          child: DonutChart(slices: [for (final (c, v) in slices) (v.toDouble(), tints[c.id] ?? categoryTint(c.id))]),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AmountText(total, size: 22, weight: FontWeight.w700, color: p.ink),
            const SizedBox(height: 2),
            Text(tr('{period}支出', {'period': periodLabel}), style: cw(IOSText.footnote, color: p.muted)),
            const SizedBox(height: 10),
            for (final (category, value) in slices.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: tints[category.id] ?? categoryTint(category.id), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(category.name, style: cw(IOSText.footnote, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(percent(value), style: cw(IOSText.footnote, color: p.muted)),
                ]),
              ),
            // The rest, so the legend always adds up to 100 %.
            if (slices.length > 3)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: p.muted.withValues(alpha: 0.5), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('其他 {n} 类', {'n': slices.length - 3}), style: cw(IOSText.footnote, color: p.muted))),
                  Text(percent(slices.skip(3).fold<int>(0, (s, e) => s + e.$2)), style: cw(IOSText.footnote, color: p.muted)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// The month's budget, kept apart from the period summary and always named by its month
/// ("2026年10月预算"), since budgets count whole months whatever period is selected.
class _MonthBudgetCard extends StatelessWidget {
  const _MonthBudgetCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    final totalBudget = ledger.budgetFor(null, store.month);
    final monthBudgets = ledger.budgetsFor(store.month);
    final categorySum = monthBudgets.where((b) => b.categoryID != null).fold<int>(0, (s, b) => s + b.limit);
    final limit = totalBudget?.limit ?? (categorySum > 0 ? categorySum : null);
    final caption = tr('{month}预算', {'month': fmtYearMonth(store.month)});
    void edit() => showCwSheet<void>(context, (_) => StoreScope(store: store, child: BudgetEditor(budget: totalBudget)));

    if (limit == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardCaption(caption),
        const SizedBox(height: 10),
        BudgetSetupCard(onTap: edit),
      ]);
    }

    final spent = totalBudget != null
        ? ledger.spent(totalBudget, store.month)
        : monthBudgets.where((b) => b.categoryID != null).fold<int>(0, (s, b) => s + ledger.spent(b, store.month));
    final remaining = limit - spent;
    final ratio = spent / (limit <= 0 ? 1 : limit);
    Widget metric(String title, Widget value) => Expanded(
          child: Column(children: [
            Text(title, style: cw(IOSText.footnote, color: p.muted)),
            const SizedBox(height: 4),
            value,
          ]),
        );
    return Pressable(
      onTap: edit,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Without a total budget the card adds up the category budgets; 调整预算 then sets a total one.
        CardCaption(totalBudget == null ? '$caption · ${tr('分类预算合计')}' : caption, trailing: tr('调整预算'), onTap: edit),
        const SizedBox(height: 10),
        CwCard(
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              metric(tr('已花'), AmountText(spent, size: IOSText.body, weight: FontWeight.w600, color: p.ink)),
              metric(tr('预算'), AmountText(limit, size: IOSText.body, weight: FontWeight.w600, color: p.ink)),
              metric(
                remaining < 0 ? tr('超出预算') : tr('剩余'),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  AmountText(remaining.abs(), size: IOSText.body, weight: FontWeight.w600, sign: '', color: remaining < 0 ? p.over : p.ink),
                  const SizedBox(width: 4),
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: remaining < 0 ? p.over : p.under, shape: BoxShape.circle)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            BudgetBar(ratio: ratio, height: 8),
            const SizedBox(height: 8),
            BudgetUsageLine(ratio: ratio),
          ]),
        ),
      ]),
    );
  }
}

/// Copilot "monthly metrics" block: spent · budget · left / over.
class BudgetCard extends StatelessWidget {
  const BudgetCard({super.key, required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final spent = store.ledger.spent(budget, store.month);
    final remaining = budget.limit - spent;
    final ratio = spent / (budget.limit <= 0 ? 1 : budget.limit);
    final name = budget.categoryID == null ? tr('月度总预算') : tr('{name}预算', {'name': store.category(budget.categoryID!)?.name ?? tr('分类')});
    Widget metric(String title, Widget value) => Expanded(
          child: Column(children: [
            Text(title, style: cw(IOSText.footnote, color: p.muted)),
            const SizedBox(height: 4),
            value,
          ]),
        );
    void adjust() => showCwSheet<void>(context, (_) => StoreScope(store: store, child: BudgetEditor(budget: budget)));
    // A one-month budget says so in the title; the every-month one needs no label.
    final title = budget.month == null ? name : '$name · ${tr('仅 {month}', {'month': fmtYearMonth(budget.month!)})}';
    return Pressable(
      onTap: adjust,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(title, trailing: tr('调整预算'), onTap: adjust),
      const SizedBox(height: 10),
      CwCard(
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            metric(tr('已花'), AmountText(spent, size: IOSText.body, weight: FontWeight.w600, color: p.ink)),
            metric(tr('预算'), AmountText(budget.limit, size: IOSText.body, weight: FontWeight.w600, color: p.ink)),
            metric(
              remaining < 0 ? tr('超出') : tr('剩余'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                AmountText(remaining.abs(), size: IOSText.body, weight: FontWeight.w600, sign: '', color: p.ink),
                const SizedBox(width: 4),
                Container(width: 6, height: 6, decoration: BoxDecoration(color: remaining < 0 ? p.over : p.under, shape: BoxShape.circle)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          BudgetBar(ratio: ratio, height: 8),
          const SizedBox(height: 8),
          BudgetUsageLine(ratio: ratio),
        ]),
      ),
    ]),
    );
  }
}

class BudgetEditor extends StatefulWidget {
  const BudgetEditor({super.key, this.budget, this.categoryID});
  final Budget? budget;
  final String? categoryID;

  @override
  State<BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<BudgetEditor> {
  late String _categoryID = widget.budget?.categoryID ?? widget.categoryID ?? '';

  /// true: 本月预算 (only the month being viewed); false: 每月预算.
  late bool _thisMonthOnly = widget.budget?.month != null;
  late final TextEditingController _amount = TextEditingController(text: widget.budget == null ? '' : Money.input(widget.budget!.limit));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Checked as you type; 保存 stays off while there is an error or nothing entered.
  String? get _amountError {
    final text = _amount.text.trim();
    if (text.isEmpty) return null;
    try {
      final cents = Money.parse(text);
      if (cents <= 0) return tr('预算需大于 0；不需要这项预算可以删除');
      return null;
    } on LedgerError {
      return tr('请输入有效金额');
    }
  }

  bool get _canSave => _amount.text.trim().isNotEmpty && _amountError == null;

  void _save() {
    final store = StoreScope.read(context);
    try {
      final original = widget.budget;
      final target = _categoryID.isEmpty ? null : _categoryID;
      final month = _thisMonthOnly ? DateTime(store.month.year, store.month.month) : null;
      bool sameScope(Budget b) =>
          b.categoryID == target && (b.month == null ? month == null : month != null && b.appliesTo(month));
      // Turning a 每月预算 into a 本月预算 adds an override for this month and keeps the recurring one.
      final keepOriginal = original != null && original.month == null && month != null;
      final slot = store.ledger.budgets.where(sameScope).firstOrNullValue;
      final budget = Budget(
        id: slot?.id ?? (original != null && !keepOriginal ? original.id : null),
        categoryID: target,
        limit: Money.parse(_amount.text.replaceAll('。', '.').replaceAll('．', '.')),
        month: month,
      );
      void apply(Ledger ledger) {
        ledger.budgets.removeWhere((b) => b.id == budget.id);
        if (original != null && !keepOriginal && original.id != budget.id) ledger.budgets.removeWhere((b) => b.id == original.id);
        ledger.budgets.add(budget);
      }

      final next = store.ledger.copy();
      apply(next);
      next.validate();
      if (store.commit(apply)) {
        Navigator.of(context).pop();
      }
    } on LedgerError catch (e) {
      showCwAlert(context, tr('请检查输入'), e.message);
    }
  }

  Future<void> _delete() async {
    final store = StoreScope.read(context);
    final navigator = Navigator.of(context);
    if (await confirmDestructive(context, tr('删除这项预算？不会删除账单。'), tr('删除预算'))) {
      if (store.commit((ledger) => ledger.budgets.removeWhere((b) => b.id == widget.budget?.id))) navigator.pop();
    }
  }

  /// What the chosen 范围 counts, in one line under the card.
  String _scopeFooter(LedgerStore store) {
    if (_categoryID.isEmpty) return tr('统计当月所有支出，和各分类预算分开计算，不会相加。');
    final name = store.category(_categoryID)?.name ?? tr('分类');
    return store.ledger.childrenOf(_categoryID).isEmpty
        ? tr('只统计「{name}」的支出。', {'name': name})
        : tr('统计「{name}」及其所有子分类的支出。', {'name': name});
  }

  /// 范围 opens the same emoji-grid category sheet as 记一笔, with 全部支出 first.
  Future<void> _chooseScope() async {
    final store = StoreScope.read(context);
    FocusScope.of(context).unfocus();
    final id = await showCwSheet<String>(
      context,
      (_) => StoreScope(
        store: store,
        child: CategoryChooser(
          kind: EntryKind.expense,
          selectedID: _categoryID,
          title: tr('选择范围'),
          leadingLabel: tr('全部支出'),
          parentSubtitle: tr('含子分类'),
          showAdd: false,
        ),
      ),
    );
    if (id != null && mounted) setState(() => _categoryID = id);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SheetScaffold(
      title: widget.budget == null ? tr('新预算') : tr('编辑预算'),
      trailingLabel: tr('保存'),
      onTrailing: _canSave ? _save : null,
      // Same insets as 设置: 16 pt to the cards' edges.
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.fromLTRB(16, 18, 16, 32), children: [
        CapsuleSegments<bool>(
          values: const [true, false],
          selected: _thisMonthOnly,
          label: (onlyThisMonth) => onlyThisMonth ? tr('本月预算') : tr('每月预算'),
          onChanged: (value) => setState(() => _thisMonthOnly = value),
        ),
        const SizedBox(height: 8),
        Text(
          _thisMonthOnly
              ? tr('只在 {month} 生效，这个月会替代每月预算。', {'month': fmtYearMonth(store.month)})
              : tr('每个月自动生效；某个月另设了本月预算时，以本月预算为准。'),
          textAlign: TextAlign.center,
          style: cw(IOSText.footnote, color: Palette.of(context).muted),
        ),
        const SizedBox(height: 18),
        FormSection(
          footer: _scopeFooter(store),
          children: [
            FormRow(
              icon: 'chart-pie',
              label: tr('范围'),
              chevron: true,
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  _categoryID.isEmpty
                      ? tr('全部支出')
                      : store.ledger.childrenOf(_categoryID).isEmpty
                          ? store.category(_categoryID)?.name ?? tr('分类')
                          : tr('{name}（含子分类）', {'name': store.category(_categoryID)?.name ?? tr('分类')}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onTap: _chooseScope,
            ),
            LabeledField(
              icon: 'coins',
              label: tr('预算金额（{code}）', {'code': store.ledger.currency}),
              controller: _amount,
              hint: tr('例如 3000'),
              alignEnd: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoneyInputFormatter()],
              onChanged: (_) => setState(() {}),
              error: _amountError,
            ),
          ],
        ),
        if (widget.budget != null) ...[
          const SizedBox(height: 18),
          FormSection(children: [FormRow(icon: 'trash', label: tr('删除预算'), destructive: true, onTap: _delete)]),
        ],
      ]),
    );
  }
}

/// The "no budget yet" card, used wherever the app offers to set one (分类 and 概览): a Settings-style
/// icon tile, a title with one line of why, a filled 设定 capsule as the single action, and an empty
/// budget bar with this month's spending so far — a preview of what the card turns into.
class BudgetSetupCard extends StatelessWidget {
  const BudgetSetupCard({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      child: CwCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const FormIconTile('piggy-bank'),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('这个月还没有预算'), style: cw(IOSText.body, weight: FontWeight.w600, color: p.ink)),
                const SizedBox(height: 2),
                Text(tr('设定每月上限，随时知道还能花多少'), style: cw(IOSText.footnote, color: p.muted)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(99)),
              alignment: Alignment.center,
              child: Text(tr('设定'), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.onBrand)),
            ),
          ]),
          const SizedBox(height: 14),
          Container(height: 6, decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 8),
          Row(children: [
            Text(tr('本月已支出'), style: cw(IOSText.footnote, color: p.muted)),
            const Spacer(),
            AmountText(store.ledger.total(EntryKind.expense, store.month), size: IOSText.footnote, weight: FontWeight.w600, sign: '', color: p.muted, brand: false),
          ]),
        ]),
      ),
    );
  }
}

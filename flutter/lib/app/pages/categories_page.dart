import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/money.dart';
import '../charts.dart';
import '../components.dart';
import '../icons.dart';
import '../motion.dart';
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
    final hidden = topLevel.length - groups.length;
    final spentHeader = switch (store.period) { Period.day => tr('今日', {}, 'spent'), Period.month => tr('已支出'), Period.year => tr('近一年', {}, 'spent') };
    final emptyText = switch (store.period) { Period.day => tr('这一天还没有支出'), Period.month => tr('本月还没有支出'), Period.year => tr('近一年还没有支出') };
    final monthName = fmtYearMonth(store.month);

    // Colours by rank this period (largest first), so neighbouring slices and dots never share a colour.
    final topSpending = ledger.topLevelSpendingIn(store.entriesIn(store.interval));
    final tints = <String, Color>{
      for (var i = 0; i < topSpending.length; i++) topSpending[i].$1.id: categoryPalette[i % categoryPalette.length],
    };
    final trendMonths = [for (var offset = -5; offset <= 0; offset++) DateTime(store.month.year, store.month.month + offset, 1)];

    return PageList(children: [
      _PeriodSummary(spending: topSpending, tints: tints, emptyText: emptyText),
      // Rows
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // With nothing to list, the summary card above already shows the empty state.
        if (groups.isNotEmpty)
        CwCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: _CategoryTable(
                  groups: groups,
                  tints: tints,
                  spentHeader: spentHeader,
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
            Expanded(
              child: Text(
                store.period == Period.month && hidden > 0
                    ? tr('另有 {n} 个分类本月没有支出', {'n': hidden})
                    : tr('点分类查看账单；进度条为 {month} 预算', {'month': monthName}),
                style: cw(12, color: p.muted),
              ),
            ),
            // For a category that isn't listed yet (no spending this period).
            Pressable(
              onTap: () => _openBudget(context, categoryID: groups.first.head.category.id),
              child: Row(children: [
                LIcon('plus', size: 14, color: p.accent, strokeWidth: 2.5),
                const SizedBox(width: 3),
                Text(tr('分类预算'), style: cw(13, weight: FontWeight.w600, color: p.accent)),
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

/// Column titles plus the two-level rows. A top-level category with subcategories expands / collapses
/// on tap (Money Pro style); one without opens its bills directly.
class _CategoryTable extends StatefulWidget {
  const _CategoryTable({required this.groups, required this.tints, required this.spentHeader, required this.onOpen, required this.onBudget});
  final List<_CategoryGroup> groups;
  final Map<String, Color> tints;
  final String spentHeader;
  final void Function(_CategoryLine) onOpen;
  final void Function(_CategoryLine) onBudget;

  @override
  State<_CategoryTable> createState() => _CategoryTableState();
}

class _CategoryTableState extends State<_CategoryTable> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(children: [
      // Column titles live inside the card (readable over any background) and only when there are rows.
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: DefaultTextStyle.merge(
          style: cw(12, weight: FontWeight.w500, color: p.muted),
          child: Row(children: [
            Expanded(child: Text(tr('分类'))),
            SizedBox(width: 76, child: Text(widget.spentHeader, textAlign: TextAlign.right)),
            const SizedBox(width: 82),
            SizedBox(width: 62, child: Text(tr('月预算'), textAlign: TextAlign.right)),
          ]),
        ),
      ),
      Divider(height: 1, thickness: 0.5, color: p.cardStroke),
      for (final group in widget.groups) ...[
        () {
          final id = group.head.category.id;
          final open = _expanded.contains(id);
          final expandable = group.children.isNotEmpty;
          return _CategoryRow(
            line: group.head,
            tint: widget.tints[group.head.category.id],
            expanded: expandable ? open : null,
            onOpen: expandable
                ? () {
                    tick();
                    setState(() => open ? _expanded.remove(id) : _expanded.add(id));
                  }
                : () => widget.onOpen(group.head),
            onBudget: () => widget.onBudget(group.head),
          );
        }(),
        AnimatedSize(
          duration: IOSMotion.smoothCurve.duration,
          curve: IOSMotion.smoothCurve,
          alignment: Alignment.topCenter,
          child: _expanded.contains(group.head.category.id)
              ? Column(children: [
                  for (final child in group.children)
                    _CategoryRow(
                      line: child,
                      child: true,
                      onOpen: () => widget.onOpen(child),
                      onBudget: () => widget.onBudget(child),
                    ),
                ])
              : const SizedBox(width: double.infinity),
        ),
      ],
    ]);
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.line, this.tint, this.expanded, this.child = false, required this.onOpen, required this.onBudget});
  final _CategoryLine line;

  /// Dot colour matching the donut (rank colour); falls back to the category's own colour.
  final Color? tint;

  /// null: no subcategories; otherwise whether they are shown (draws a disclosure chevron).
  final bool? expanded;

  /// A subcategory row: indented, a little smaller, no colour dot.
  final bool child;
  LedgerCategory get category => line.category;
  int get spent => line.spent;
  Budget? get budget => line.budget;
  int get monthSpent => line.monthSpent;

  /// Name, amount and bar: this category's bills.
  final VoidCallback onOpen;

  /// Only the right-hand "设预算 / 预算金额" cell edits the budget.
  final VoidCallback onBudget;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final tint = this.tint ?? categoryTint(category.id);
    final ratio = budget == null ? 0.0 : monthSpent / (budget!.limit <= 0 ? 1 : budget!.limit);
    return Row(children: [
      Expanded(
        child: Pressable(
          semanticLabel: tr('{name}的账单', {'name': category.name}),
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: child ? 11 : 14),
            child: Row(children: [
              if (child)
                const SizedBox(width: 15)
              else ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              SizedBox(width: 18, child: CategoryIcon(category, size: child ? 14 : 15, color: tint)),
              const SizedBox(width: 8),
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(line.directOnly ? tr('未细分') : category.name,
                        style: cw(child ? 14 : 15, weight: FontWeight.w400, color: child ? p.ink.withValues(alpha: 0.85) : p.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (expanded != null) ...[
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: expanded! ? 0.25 : 0,
                      duration: IOSMotion.snappyCurve.duration,
                      curve: IOSMotion.snappyCurve,
                      child: LIcon('chevron-right', size: 18, color: p.muted, strokeWidth: 2.2),
                    ),
                  ],
                ]),
              ),
              SizedBox(
                width: 76,
                child: Align(
                    alignment: Alignment.centerRight,
                    child: AmountText(spent, size: child ? 13 : 14, weight: child ? FontWeight.w400 : FontWeight.w600, color: p.ink)),
              ),
              const SizedBox(width: 8),
              // The bar is this month's budget progress; without a budget there is nothing to show.
              SizedBox(width: 66, child: budget == null ? null : BudgetBar(ratio: ratio)),
            ]),
          ),
        ),
      ),
      // The "未细分" row shares its parent's budget, which the parent row already shows.
      if (line.directOnly)
        const SizedBox(width: 70)
      else
      Pressable(
        semanticLabel: budget == null ? tr('为{name}设预算', {'name': category.name}) : tr('修改{name}预算', {'name': category.name}),
        onTap: onBudget,
        child: Padding(
          padding: EdgeInsets.only(left: 8, top: child ? 11 : 14, bottom: child ? 11 : 14),
          child: SizedBox(
            width: 62,
            child: Align(
              alignment: Alignment.centerRight,
              child: budget == null
                  ? Text(tr('设预算'), style: cw(13, color: p.accent))
                  : AmountText(budget!.limit, size: 13, weight: FontWeight.w400, color: p.accent),
            ),
          ),
        ),
      ),
    ]);
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
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
            Text(tr('{period}支出', {'period': periodLabel}), style: cw(13, color: p.muted)),
            const SizedBox(height: 10),
            for (final (category, value) in slices.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: tints[category.id] ?? categoryTint(category.id), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(category.name, style: cw(13, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(percent(value), style: cw(13, color: p.muted)),
                ]),
              ),
            // The rest, so the legend always adds up to 100 %.
            if (slices.length > 3)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: p.muted.withValues(alpha: 0.5), shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('其他 {n} 类', {'n': slices.length - 3}), style: cw(13, color: p.muted))),
                  Text(percent(slices.skip(3).fold<int>(0, (s, e) => s + e.$2)), style: cw(13, color: p.muted)),
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
        Pressable(
          onTap: edit,
          child: CwCard(
            child: Row(children: [
              LIcon('piggy-bank', size: 20, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('这个月还没有预算'), style: cw(15, color: p.ink))),
              Text(tr('设预算'), style: cw(15, weight: FontWeight.w600, color: p.accent)),
            ]),
          ),
        ),
      ]);
    }

    final spent = totalBudget != null
        ? ledger.spent(totalBudget, store.month)
        : monthBudgets.where((b) => b.categoryID != null).fold<int>(0, (s, b) => s + ledger.spent(b, store.month));
    final remaining = limit - spent;
    final ratio = spent / (limit <= 0 ? 1 : limit);
    Widget metric(String title, Widget value) => Expanded(
          child: Column(children: [
            Text(title, style: cw(12, color: p.muted)),
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
              metric(tr('已花'), AmountText(spent, size: 16, weight: FontWeight.w700, color: p.ink)),
              metric(tr('预算'), AmountText(limit, size: 16, weight: FontWeight.w700, color: p.ink)),
              metric(
                remaining < 0 ? tr('超出预算') : tr('剩余'),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  AmountText(remaining.abs(), size: 16, weight: FontWeight.w700, sign: '', color: remaining < 0 ? p.over : p.ink),
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
            Text(title, style: cw(12, color: p.muted)),
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
            metric(tr('已花'), AmountText(spent, size: 16, weight: FontWeight.w700, color: p.ink)),
            metric(tr('预算'), AmountText(budget.limit, size: 16, weight: FontWeight.w700, color: p.ink)),
            metric(
              remaining < 0 ? tr('超出') : tr('剩余'),
              Row(mainAxisSize: MainAxisSize.min, children: [
                AmountText(remaining.abs(), size: 16, weight: FontWeight.w700, sign: '', color: p.ink),
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

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final expenseCategories = store.ledger.categories.where((c) => c.kind == EntryKind.expense).toList();
    final options = ['', ...expenseCategories.map((c) => c.id)];
    return SheetScaffold(
      title: widget.budget == null ? tr('新预算') : tr('编辑预算'),
      trailingLabel: tr('保存'),
      onTrailing: _canSave ? _save : null,
      body: ListView(padding: const EdgeInsets.all(18), children: [
        CapsuleSegments<bool>(
          values: const [true, false],
          selected: _thisMonthOnly,
          label: (onlyThisMonth) => onlyThisMonth ? tr('本月预算') : tr('每月预算'),
          onChanged: (value) => setState(() => _thisMonthOnly = value),
        ),
        const SizedBox(height: 8),
        Text(
          _thisMonthOnly
              ? tr('只在 {month} 有效；这个月会优先使用它，而不是每月预算。', {'month': fmtYearMonth(store.month)})
              : tr('每个月都会自动套用。'),
          textAlign: TextAlign.center,
          style: cw(12, color: Palette.of(context).muted),
        ),
        const SizedBox(height: 18),
        FormSection(
          footer: tr('每个范围可以有一个每月预算，并为某个月另设本月预算。总预算与分类预算各自独立，不相加。一级分类的预算包含它所有子分类的支出，和分类列表的合计一致。'),
          children: [
            FormRow(
              icon: 'chart-pie',
              label: tr('范围'),
              trailing: MenuPicker<String>(
                value: _categoryID,
                options: options,
                label: (id) {
                  if (id.isEmpty) return tr('全部支出');
                  final name = store.category(id)?.name ?? tr('分类');
                  return store.ledger.childrenOf(id).isEmpty ? name : tr('{name}（含子分类）', {'name': name});
                },
                onChanged: (id) => setState(() => _categoryID = id),
              ),
            ),
            LabeledField(
              icon: 'banknote',
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

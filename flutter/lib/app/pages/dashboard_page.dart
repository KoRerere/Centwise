import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../charts.dart';
import '../components.dart';
import '../entry_editor.dart';
import '../icons.dart';
import '../sheets.dart';
import '../store.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import 'categories_page.dart' show BudgetCard, BudgetEditor;
import 'transactions_page.dart' show TransactionsPage;

/// Overview: what was spent (spend card, or the year card), the bills behind it, and what is left of this month's budget.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onShowTransactions, required this.onNewEntry});
  final VoidCallback onShowTransactions;
  final VoidCallback onNewEntry;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final ledger = store.ledger;
    final totalBudget = [if (ledger.budgetFor(null, store.month) case final budget?) budget];
    return PageList(children: [
      if (store.period == Period.year) const _YearCard() else const _SpendCard(),
      if (ledger.entries.isEmpty)
        CwCard(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
          child: Column(children: [
            LIcon('pencil', size: 30, color: p.muted),
            const SizedBox(height: 10),
            Text(tr('从今天的第一笔开始'), style: cw(17, weight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 6),
            Text(tr('点右下角加号记下收支，或在设置里导入旧账本。'), textAlign: TextAlign.center, style: cw(13, color: p.muted)),
          ]),
        )
      // 近一年: what the year went on, by category, instead of a list of individual bills.
      else if (store.period == Period.year)
        const _YearCategoryGrid()
      else
        _RecentCard(onShowTransactions: onShowTransactions, onNewEntry: onNewEntry),
      if (totalBudget.isNotEmpty)
        BudgetCard(budget: totalBudget.first)
      else
        Pressable(
          onTap: () => showCwSheet<void>(context, (_) => StoreScope(store: store, child: const BudgetEditor())),
          child: CwCard(
            child: Row(children: [
              LIcon('piggy-bank', size: 20, color: p.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('设一个本月预算，随时看还剩多少'), style: cw(15, color: p.ink))),
              Text(tr('设预算'), style: cw(15, weight: FontWeight.w600, color: p.accent)),
            ]),
          ),
        ),
    ]);
  }
}

/// Scrollable page body with the shared gutters and room for the floating controls.
class PageList extends StatelessWidget {
  const PageList({super.key, required this.children, this.spacing = 18});
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomControlsClearance(context)),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            // New period → the figures settle in rather than snapping.
            child: ContentTransition(
              trigger: '${store.period}|${store.month}',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]]
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

void openEntry(BuildContext context, Entry entry) {
  final store = StoreScope.read(context);
  showCwSheet<void>(context, (_) => StoreScope(store: store, child: EntryEditor(entry: entry)), guarded: true);
}

class _SpendCard extends StatelessWidget {
  const _SpendCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final series = SpendSeries.of(store);
    final difference = series.currentTotal - series.previousAtSameStep;
    final over = difference > 0;
    final isDay = store.period == Period.day;
    // Compared with the same point of the previous period — not with a budget, so no "超出".
    final String comparison;
    if (difference == 0) {
      comparison = isDay ? (store.isCurrentPeriod ? tr('与昨天同期持平') : tr('与前一天同期持平')) : tr('与上月同期持平');
    } else if (isDay) {
      comparison = store.isCurrentPeriod
          ? (over ? tr('比昨天同期多花 {amount}') : tr('比昨天同期少花 {amount}'))
          : (over ? tr('比前一天同期多花 {amount}') : tr('比前一天同期少花 {amount}'));
    } else {
      comparison = over ? tr('比上月同期多花 {amount}') : tr('比上月同期少花 {amount}');
    }
    final (start, _) = store.interval;
    final lastDay = DateTime(start.year, start.month + 1, 0);
    final ticks = isDay
        ? const ['00:00', '12:00', '24:00']
        : [fmtMonthDay(start), fmtMonthDay(DateTime(start.year, start.month, 15)), fmtMonthDay(lastDay)];
    final periodLabel = store.isCurrentPeriod ? store.periodWord : store.periodName;
    // Three levels, top to bottom: small label · the amount · a plain-text comparison.
    return CwCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('{period}支出', {'period': periodLabel}), style: cw(13, color: p.muted)),
        const SizedBox(height: 4),
        AmountText(series.currentTotal, size: 34, weight: FontWeight.w700, color: p.ink),
        const SizedBox(height: 4),
        Row(children: [
          if (difference != 0) ...[
            LIcon(over ? 'arrow-up-right' : 'arrow-down-left', size: 14, color: over ? p.over : p.under, strokeWidth: 2.5),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: TextWithAmount(comparison, difference.abs(),
                style: cw(13, color: p.muted), amountColor: difference == 0 ? null : (over ? p.over : p.under)),
          ),
        ]),
        const SizedBox(height: 14),
        Semantics(
          label: isDay ? tr('今天累计支出走势，虚线为昨天') : tr('本月累计支出走势，虚线为上月'),
          child: CumulativeChart(
            current: series.current,
            previous: series.previous,
            domainMax: series.steps,
            ticks: ticks,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _legendLine(p.brand, false),
          const SizedBox(width: 5),
          Text(periodLabel, style: cw(12, color: p.muted)),
          const SizedBox(width: 14),
          _legendLine(p.muted.withValues(alpha: 0.7), true),
          const SizedBox(width: 5),
          Text(isDay ? (store.isCurrentPeriod ? tr('昨天') : tr('前一天')) : tr('上月'), style: cw(12, color: p.muted)),
        ]),
      ]),
    );
  }

  static Widget _legendLine(Color color, bool dashed) => SizedBox(
        width: 16,
        height: 2,
        child: Row(children: [
          for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(child: Container(height: 2, color: color)),
          ],
        ]),
      );
}

/// Cumulative spend through the selected period and the one before it:
/// by hour for a day (today vs yesterday), by day for a month (this month vs last).
class SpendSeries {
  SpendSeries(this.current, this.previous, this.currentTotal, this.previousAtSameStep, this.steps);
  final List<double> current;
  final List<double> previous;
  final int currentTotal;
  final int previousAtSameStep;
  final int steps;

  static SpendSeries of(LedgerStore store) {
    final isDay = store.period == Period.day;
    final (start, _) = store.interval;
    final (previousStart, _) = store.previousInterval;
    int daysIn(DateTime m) => DateTime(m.year, m.month + 1, 0).day;
    // Hours: step 0 is midnight, step h+1 is the end of hour h. Days: step d-1 is the end of day d.
    final count = isDay ? 25 : daysIn(start);
    final previousCount = isDay ? 25 : daysIn(previousStart);
    int bucket(DateTime date) => isDay ? date.hour + 1 : date.day - 1;
    final now = DateTime.now();

    List<int> perStep((DateTime, DateTime) range, int length) {
      final values = List<int>.filled(length, 0);
      for (final entry in store.entriesIn(range)) {
        if (entry.kind != EntryKind.expense) continue;
        final index = bucket(entry.date);
        if (index >= 0 && index < length) values[index] += entry.amount;
      }
      return values;
    }

    final thisSteps = perStep(store.interval, count);
    // The current period's line runs to "now", or further when entries are dated later
    // (e.g. an expense booked ahead for this evening), so the total always includes every entry.
    var lastStep = store.isCurrentPeriod ? (isDay ? now.hour + 1 : now.day - 1) : count - 1;
    for (var i = count - 1; i > lastStep; i--) {
      if (thisSteps[i] != 0) {
        lastStep = i;
        break;
      }
    }
    final lastSteps = perStep(store.previousInterval, previousCount);
    final current = <double>[];
    var running = 0;
    for (var i = 0; i <= lastStep && i < count; i++) {
      running += thisSteps[i];
      current.add(running / 100);
    }
    final currentTotal = running;
    final previous = <double>[];
    running = 0;
    var atSame = 0;
    for (var i = 0; i < previousCount; i++) {
      running += lastSteps[i];
      previous.add(running / 100);
      if (i == (lastStep < previousCount ? lastStep : previousCount - 1)) atSame = running;
    }
    return SpendSeries(current, previous, currentTotal, atSame, count);
  }
}

class _YearCard extends StatelessWidget {
  const _YearCard();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final months = store.yearMonths;
    final total = months.fold<int>(0, (s, m) => s + m.expense);
    final incomeTotal = months.fold<int>(0, (s, m) => s + m.income);
    final average = store.monthlyAverage(EntryKind.expense);
    final averageIncome = store.monthlyAverage(EntryKind.income);
    final highlight = months.indexWhere((m) => m.month.year == store.month.year && m.month.month == store.month.month);
    Widget metric(String title, int value, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            Expanded(child: Text(title, style: cw(15, weight: FontWeight.w400, color: p.ink))),
            AmountText(value, size: 16, weight: FontWeight.w700, color: color),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CwCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('{period}支出', {'period': store.isCurrentPeriod ? store.periodWord : store.periodName}), style: cw(13, color: p.muted)),
              const SizedBox(height: 4),
              AmountText(total, size: 34, weight: FontWeight.w700, color: p.ink),
              const SizedBox(height: 4),
              TextWithAmount(tr('平均每月 {amount}'), average, style: cw(13, color: p.muted)),
            ]),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: tr('近一年每月支出，虚线为月均'),
            child: MonthBarsChart(
              values: [for (final m in months) m.expense],
              labels: [for (final m in months) '${m.month.month}'],
              average: average,
              highlight: highlight,
            ),
          ),
          const SizedBox(height: 8),
          Text('${store.yearRangeText} · ${tr('红色高于月均，绿色低于月均')}', style: cw(11, color: p.muted)),
        ]),
      ),
      const SizedBox(height: 18),
      CardCaption(tr('年度指标'), trailing: tr('按 {n} 个月平均', {'n': store.averageMonthCount})),
      const SizedBox(height: 10),
      CwCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Column(children: [
          metric(tr('近一年总支出'), total, p.ink),
          Divider(height: 1, color: p.track),
          metric(tr('平均每月支出'), average, p.ink),
          Divider(height: 1, color: p.track),
          metric(tr('近一年总收入'), incomeTotal, p.income),
          Divider(height: 1, color: p.track),
          metric(tr('平均每月结余'), averageIncome - average, averageIncome - average >= 0 ? p.income : p.over),
        ]),
      ),
    ]);
  }
}

/// 近一年 spending per top-level category (subcategories included), four to a row, largest first.
/// A tile opens that category's bills for the year.
class _YearCategoryGrid extends StatelessWidget {
  const _YearCategoryGrid();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final spending = store.ledger.topLevelSpendingIn(store.entriesIn(store.interval)).where((e) => e.$2 > 0).toList();
    void open(LedgerCategory category) => showCwSheet<void>(
          context,
          (_) => StoreScope(
            store: store,
            child: SheetScaffold(title: category.name, leadingLabel: tr('完成'), body: TransactionsPage(categoryID: category.id)),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(tr('分类支出'), trailing: tr('共 {n} 类', {'n': spending.length})),
      const SizedBox(height: 10),
      CwCard(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
        child: spending.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr('近一年还没有支出'), textAlign: TextAlign.center, style: cw(14, color: p.muted)),
              )
            : LayoutBuilder(builder: (context, constraints) {
                const columns = 4;
                final width = constraints.maxWidth / columns;
                return Wrap(children: [
                  for (final (category, amount) in spending)
                    SizedBox(
                      width: width,
                      child: Pressable(
                        semanticLabel: tr('{name}的账单', {'name': category.name}),
                        onTap: () => open(category),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(children: [
                            // One line-icon style and one colour for every tile, so 20+ categories read as a calm grid.
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.1), shape: BoxShape.circle),
                              child: Center(child: DuoIcon(categoryIcon(category), size: 22, color: p.brandDeep, detailColor: Color.lerp(p.accent, p.card, 0.45))),
                            ),
                            const SizedBox(height: 6),
                            Text(category.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(12, color: p.muted)),
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: AmountText(amount, size: 13, weight: FontWeight.w600, color: p.ink),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]);
              }),
      ),
    ]);
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.onShowTransactions, required this.onNewEntry});
  final VoidCallback onShowTransactions;
  final VoidCallback onNewEntry;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries = store.periodEntries;
    final empty = switch (store.period) { Period.day => tr('这一天还没有记录'), Period.month => tr('这个月还没有记录'), Period.year => tr('近一年还没有记录') };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CardCaption(tr('最近账单'),
          trailing: entries.isEmpty ? null : tr('共 {n} 笔消费', {'n': entries.length}), onTap: onShowTransactions),
      const SizedBox(height: 10),
      CwCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: entries.isEmpty
            ? EmptyState(
                icon: 'receipt',
                illustration: 'receipt',
                title: empty,
                message: store.isCurrentPeriod ? tr('花了什么、收了什么，随手记一笔') : null,
                actionLabel: store.loadingFailed ? null : tr('记一笔'),
                onAction: onNewEntry,
              )
            : Column(children: [
                for (final (day, items) in groupedByDay(entries.take(6))) ...[
                  Padding(padding: const EdgeInsets.only(top: 10, bottom: 2), child: DayHeading(day)),
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const RowDivider(),
                    EntryRow(entry: items[i], onTap: () => openEntry(context, items[i])),
                  ],
                ]
              ]),
      ),
    ]);
  }
}


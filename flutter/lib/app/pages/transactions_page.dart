import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../components.dart';
import '../icons.dart';
import '../store.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';
import 'dashboard_page.dart' show openEntry;

/// Copilot "Transactions": search card with a type filter, period total, entries grouped by day.
///
/// Also used, with [categoryID], as one category's bill list (opened from the 分类 page), following the
/// period selected there.
class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, this.searchRequest, this.categoryID, this.includeSubcategories = true});

  /// Set to true by the header magnifier: focus the search field and search all dates.
  final ValueNotifier<bool>? searchRequest;

  /// Only bills with a share in this category.
  final String? categoryID;

  /// With [categoryID]: also list bills filed under its subcategories (false = that category only).
  final bool includeSubcategories;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  EntryKind? _kind;

  /// Search scope: false = the period selected below (当前时段), true = every date.
  bool _allDates = false;
  (DateTime, DateTime)? _seenInterval;

  @override
  void initState() {
    super.initState();
    widget.searchRequest?.addListener(_onSearchRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSearchRequest());
  }

  @override
  void dispose() {
    widget.searchRequest?.removeListener(_onSearchRequest);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchRequest() {
    final request = widget.searchRequest;
    if (request == null || !request.value || !mounted) return;
    request.value = false;
    setState(() => _allDates = true);
    // Wait for the page slide to finish before the keyboard comes up.
    Future.delayed(const Duration(milliseconds: 320), () {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  Set<String>? _categoryIDs;

  int _amountOf(Entry entry) {
    final id = widget.categoryID;
    if (id == null) return entry.amount;
    final ids = _categoryIDs!;
    return entry.allocations.where((a) => ids.contains(a.categoryID)).fold<int>(0, (s, a) => s + a.amount);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final interval = store.interval;
    // Moving to another period with the capsule goes back to searching that period.
    if (_seenInterval != null && _seenInterval != interval) _allDates = false;
    _seenInterval = interval;
    final (start, end) = interval;
    final query = _search.text.trim().toLowerCase();
    final categoryID = widget.categoryID;
    _categoryIDs = categoryID == null
        ? null
        : widget.includeSubcategories
            ? store.ledger.subtreeIDs(categoryID)
            : {categoryID};
    final categoryIDs = _categoryIDs;
    final filtered = store.ledger.entries.where((entry) {
      if (!_allDates && (entry.date.isBefore(start) || !entry.date.isBefore(end))) return false;
      if (categoryIDs != null && !entry.allocations.any((a) => categoryIDs.contains(a.categoryID))) return false;
      if (_kind != null && entry.kind != _kind) return false;
      if (query.isEmpty) return true;
      final haystack = '${entry.note} ${entry.payee} ${store.categoryName(entry)} ${store.accountName(entry.accountID)}'.toLowerCase();
      return haystack.contains(query);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final total = filtered
        .where((e) => !e.pending && (_kind != null || categoryID != null || e.kind == EntryKind.expense))
        .fold<int>(0, (s, e) => s + _amountOf(e));
    final scopeName = store.periodName;
    final heading = _allDates ? tr('全部日期') : switch (store.period) {
      Period.day => DayHeading.label(store.month) == tr('今天') || DayHeading.label(store.month) == tr('昨天')
          ? tr('{date} {day}', {'date': fmtMonthDay(store.month), 'day': DayHeading.label(store.month)})
          : DayHeading.label(store.month),
      Period.month => fmtYearMonth(store.month),
      Period.year => store.periodName,
    };
    final totalLabel = _kind != null
        ? _kind!.title
        : categoryID != null
            ? tr('该分类')
            : _allDates
                ? tr('全部日期支出')
                : tr('{period}支出', {'period': store.period == Period.day ? tr('当天', {}, 'period') : store.periodWord});
    final emptyLabel = query.isNotEmpty
        ? (_allDates
            ? tr('全部日期中没有找到“{query}”', {'query': _search.text.trim()})
            : tr('{scope}没有找到“{query}”', {'scope': scopeName, 'query': _search.text.trim()}))
        : _allDates
            ? tr('还没有符合条件的账单')
            : switch (store.period) { Period.day => tr('这一天没有符合条件的账单'), Period.month => tr('这个月没有符合条件的账单'), Period.year => tr('近一年没有符合条件的账单') };
    final groups = groupedByDay(filtered);
    // A filter that isn't the default is always spelled out, with a one-tap way back.
    final filterChip = _kind == null
        ? null
        : Padding(
            padding: EdgeInsets.zero,
            child: Row(children: [
              Pressable(
                semanticLabel: tr('清除筛选'),
                onTap: () => setState(() => _kind = null),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  // Solid card colour: the chip sits on the blue header, where a tinted fill would vanish.
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('类型：{kind}', {'kind': _kind!.title}), style: cw(13, weight: FontWeight.w600, color: p.accent)),
                    const SizedBox(width: 4),
                    LIcon('x', size: 14, color: p.accent, strokeWidth: 2.5),
                  ]),
                ),
              ),
            ]),
          );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ContentTransition(
        trigger: '${store.period}|${store.month}',
        child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _searchCard(p),
                if (filterChip != null) ...[const SizedBox(height: 10), filterChip],
              ]),
            ),
          ),
          // The list sits on a card-coloured panel with rounded top corners, so the text stays
          // readable over the blue header gradient.
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            sliver: SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverMainAxisGroup(slivers: [
                SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: Text(heading, style: cw(22, weight: FontWeight.w700, color: p.ink))),
                      AmountText(total, size: 20, weight: FontWeight.w700, sign: '', color: p.ink),
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                        child: Text(tr('{n} 笔 · 合计为{label}', {'n': filtered.length, 'label': totalLabel}), style: cw(12, color: p.muted)),
                      ),
                      // The bottom capsule is the only period control; searching from the header magnifier
                      // looks through every date, and this goes back to the selected period.
                      if (_allDates)
                        Pressable(
                          onTap: () => setState(() => _allDates = false),
                          child: Text(tr('只看{scope}', {'scope': scopeName}), style: cw(12, weight: FontWeight.w600, color: p.accent)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(children: [
                          EmptyState(icon: 'folder-search', illustration: query.isNotEmpty ? 'search' : 'receipt', title: emptyLabel),
                          if (_kind != null) ...[
                            const SizedBox(height: 12),
                            Pressable(
                              onTap: () => setState(() => _kind = null),
                              child: Text(tr('清除筛选'), style: cw(14, weight: FontWeight.w600, color: p.accent)),
                            ),
                          ],
                          if (query.isNotEmpty && !_allDates) ...[
                            const SizedBox(height: 12),
                            Pressable(
                              onTap: () => setState(() => _allDates = true),
                              child: Text(tr('改为搜索全部日期'), style: cw(14, weight: FontWeight.w600, color: p.accent)),
                            ),
                          ],
                        ]),
                      ),
                  ]),
                ),
                SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final (day, items) = groups[index];
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(padding: const EdgeInsets.only(top: 18, bottom: 2), child: DayHeading(day)),
                      for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const RowDivider(),
                    EntryRow(entry: items[i], onTap: () => openEntry(context, items[i])),
                  ],
                    ]);
                  },
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomControlsClearance(context))),
              ]),
            ),
          ),
          ),
          // Keep the panel running to the bottom edge when the list is short.
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverFillRemaining(hasScrollBody: false, child: ColoredBox(color: p.card)),
          ),
        ],
      ),
      ),
    );
  }

  Widget _searchCard(Palette p) {
    String kindLabel(EntryKind? kind) => kind == null ? tr('全部') : kind.title;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.cardStroke, width: 0.75),
      ),
      child: Row(children: [
        LIcon('search', size: 18, color: p.muted),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            autocorrect: false,
            style: cw(16, color: p.ink),
            decoration: InputDecoration(hintText: tr('搜索备注、分类、账户、交易对象'), contentPadding: EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        if (_search.text.isNotEmpty)
          Pressable(
            semanticLabel: tr('清除搜索'),
            onTap: () => setState(_search.clear),
            child: Padding(padding: const EdgeInsets.all(4), child: LIcon('circle-x', size: 18, color: p.muted)),
          ),
        if (widget.categoryID == null)
        PopupMenuButton<String>(
          tooltip: tr('按类型筛选'),
          initialValue: _kind?.name ?? 'all',
          color: p.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          position: PopupMenuPosition.under,
          // A null item value would be treated as "cancelled", so "all" is a string key.
          onSelected: (key) => setState(() => _kind = key == 'all' ? null : EntryKind.parse(key)),
          itemBuilder: (context) => [
            for (final kind in <EntryKind?>[null, EntryKind.expense, EntryKind.income, EntryKind.transfer, EntryKind.adjustment])
              PopupMenuItem<String>(
                value: kind?.name ?? 'all',
                child: Row(children: [
                  Expanded(child: Text(kindLabel(kind), style: cw(15, weight: FontWeight.w400, color: p.ink))),
                  if (kind == _kind) LIcon('check', size: 16, color: p.accent),
                ]),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: LIcon('list-filter', size: 18, color: _kind == null ? p.muted : p.accent, strokeWidth: _kind == null ? 2 : 2.5),
          ),
        ),
      ]),
    );
  }
}

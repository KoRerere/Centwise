import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../components.dart';
import '../icons.dart';
import '../sheets.dart' show PullDownItem, showPullDownMenu;
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
    final headerRows = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(heading, style: cw(19, weight: FontWeight.w700, color: p.ink))),
        AmountText(total, size: 20, weight: FontWeight.w700, sign: '', color: p.ink),
      ]),
      // "n 笔 · 合计为…" helps for a month or a year; a single day's list says it all already.
      // (While searching all dates it stays, with the 只看… link.)
      if (store.period != Period.day || _allDates) ...[
      const SizedBox(height: 2),
      Row(children: [
        Expanded(
          child: Text(tr('{n} 笔 · 合计为{label}', {'n': filtered.length, 'label': totalLabel}), style: cw(IOSText.footnote, color: p.muted)),
        ),
        // The bottom capsule is the only period control; searching from the header magnifier
        // looks through every date, and this goes back to the selected period.
        if (_allDates)
          Pressable(
            onTap: () => setState(() => _allDates = false),
            child: Text(tr('只看{scope}', {'scope': scopeName}), style: cw(IOSText.footnote, weight: FontWeight.w600, color: p.accent)),
          ),
      ]),
      ],
    ];

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ContentTransition(
        trigger: '${store.period}|${store.month}',
        child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            // Top: the page's own gutter plus the floating header the content scrolls up behind.
            padding: EdgeInsets.fromLTRB(16, 4 + HeaderInset.of(context), 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _searchCard(p),
              ]),
            ),
          ),
          if (filtered.isEmpty)
            // No bills: one rounded card that fills the rest of the screen, ending a little above the
            // floating bottom controls, with the dotted empty state taking all the space under the heading.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverFillRemaining(
                hasScrollBody: false,
                // The gap under the card lives inside the fill (a SliverPadding after it would push the
                // card's end below the screen).
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomControlsClearance(context, extra: 12)),
                  child: Container(
                  constraints: const BoxConstraints(minHeight: 360),
                  decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(15)),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    ...headerRows,
                    const SizedBox(height: 20),
                    // The dotted canvas runs edge to edge across the card and down to its bottom edge.
                    Expanded(
                      child: EmptyState(icon: 'folder-search', illustration: query.isNotEmpty ? 'search' : 'receipt', title: emptyLabel, bleed: 20, bleedBottom: 20,
                          // Above centre: the eye expects it in the upper part of a tall card.
                          alignment: const Alignment(0, -0.4)),
                    ),
                    if (_kind != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: Pressable(
                            onTap: () => setState(() => _kind = null),
                            child: Text(tr('清除筛选'), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.accent)),
                          ),
                        ),
                      ),
                    if (query.isNotEmpty && !_allDates)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: Pressable(
                            onTap: () => setState(() => _allDates = true),
                            child: Text(tr('改为搜索全部日期'), style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.accent)),
                          ),
                        ),
                      ),
                  ]),
                ),
                ),
              ),
            )
          else ...[
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
                    ...headerRows,
                    const SizedBox(height: 4),
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
        ],
      ),
      ),
    );
  }

  Widget _searchCard(Palette p) {
    String kindLabel(EntryKind? kind) => kind == null ? tr('全部') : kind.title;
    // iOS 26 Settings-style search: a Liquid Glass capsule floating at the top of the list, same
    // material as the period capsule at the bottom (real refraction on the iPhone, frost on the Mac).
    return LiquidGlass(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 50,
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
              textAlignVertical: TextAlignVertical.center,
              style: cw(IOSText.body, color: p.ink),
              // textAlignVertical centers the field in the 50 pt capsule; the 4.5 pt bottom padding
              // optically levels CJK glyphs with the magnifier.
              decoration: InputDecoration(hintText: tr('搜索'), isCollapsed: true, contentPadding: const EdgeInsets.only(bottom: 4.5)),
            ),
          ),
          if (_search.text.isNotEmpty)
            Pressable(
              semanticLabel: tr('清除搜索'),
              onTap: () => setState(_search.clear),
              child: Padding(padding: const EdgeInsets.all(4), child: LIcon('circle-x', size: 18, color: p.muted)),
            ),
          // A type filter in force is spelled out right next to its button, with a one-tap ✕ back to 全部.
          if (_kind != null && widget.categoryID == null)
            Pressable(
              semanticLabel: tr('清除筛选'),
              onTap: () => setState(() => _kind = null),
              child: Container(
                height: 28,
                padding: const EdgeInsets.fromLTRB(10, 0, 7, 0),
                decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_kind!.title, style: cw(IOSText.footnote, weight: FontWeight.w600, color: p.ink)),
                  const SizedBox(width: 3),
                  LIcon('x', size: 13, color: p.muted, strokeWidth: 2.5),
                ]),
              ),
            ),
          if (_kind != null && widget.categoryID == null) const SizedBox(width: 8),
          if (widget.categoryID == null)
            // Builder: the menu needs the button's own position to open from it.
            Builder(builder: (button) => Pressable(
              semanticLabel: tr('按类型筛选'),
              // The types come up as an iOS pull-down menu right under the button.
              onTap: () async {
                // 转账 / 余额调整 can't be created any more; they are offered only while the ledger
                // still has such (older) bills to find.
                final entries = StoreScope.read(context).ledger.entries;
                final kinds = <EntryKind?>[
                  null,
                  EntryKind.expense,
                  EntryKind.income,
                  for (final k in const [EntryKind.transfer, EntryKind.adjustment])
                    if (k == _kind || entries.any((e) => e.kind == k)) k,
                ];
                final picked = await showPullDownMenu<String>(
                  button,
                  items: [
                    for (final kind in kinds)
                      PullDownItem(value: kind?.name ?? 'all', label: kindLabel(kind), checked: kind == _kind),
                  ],
                );
                if (picked != null && picked != (_kind?.name ?? 'all')) {
                  setState(() => _kind = picked == 'all' ? null : EntryKind.parse(picked));
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: LIcon('list-filter', size: 18, color: _kind == null ? p.muted : p.accent, strokeWidth: _kind == null ? 2 : 2.5),
              ),
            )),
        ]),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emoji_data.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// The full Apple emoji set for a category icon, laid out like the system emoji picker: a search
/// field, one long scrolling grid with a header per group (常用 first, then 表情与角色 … 旗帜), and a
/// row of group tabs along the bottom that jump to a group and follow the scroll.
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({super.key, required this.selected, required this.onSelected, required this.common, this.height = 420});

  /// The emoji currently chosen (highlighted wherever it appears).
  final String selected;
  final ValueChanged<String> onSelected;

  /// The 常用 group: emoji picked for bookkeeping categories.
  final List<String> common;
  final double height;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  static const _columns = 8;
  static const _headerHeight = 34.0;
  static const _hPad = 10.0;

  final _scroll = ScrollController();
  final _search = TextEditingController();
  String _query = '';
  int _activeTab = 0;

  /// Scroll offset where each section starts, recomputed for the current width.
  List<double> _offsets = const [];

  static const Map<String, IconData> _tabIcons = {
    'common': CupertinoIcons.star,
    'smiley': CupertinoIcons.smiley,
    'paw': CupertinoIcons.paw,
    'food': CupertinoIcons.cart,
    'activity': CupertinoIcons.sportscourt,
    'travel': CupertinoIcons.car_detailed,
    'objects': CupertinoIcons.lightbulb,
    'symbols': CupertinoIcons.number,
    'flags': CupertinoIcons.flag,
  };

  late final List<(String title, String icon, List<String> emojis)> _sections = [
    (tr('常用'), 'common', widget.common),
    for (final g in emojiGroups) (tr(g.title), g.icon, [for (final e in g.emojis) e.$1]),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _followScroll() {
    if (_offsets.isEmpty || !_scroll.hasClients) return;
    final y = _scroll.offset + 1;
    var tab = 0;
    for (var i = 0; i < _offsets.length; i++) {
      if (y >= _offsets[i]) tab = i;
    }
    if (tab != _activeTab) setState(() => _activeTab = tab);
  }

  void _jumpTo(int i) {
    HapticFeedback.selectionClick();
    if (_query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || i >= _offsets.length) return;
      _scroll.animateTo(_offsets[i].clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    });
    setState(() => _activeTab = i);
  }

  List<String> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    return [
      for (final g in emojiGroups)
        for (final e in g.emojis)
          if (words.every(e.$2.contains)) e.$1,
    ];
  }

  Widget _cell(String emoji, Palette p, double extent) {
    final on = emoji == widget.selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onSelected(emoji);
      },
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: extent - 4,
          height: extent - 4,
          decoration: BoxDecoration(color: on ? p.track : Colors.transparent, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(
            emoji,
            textScaler: TextScaler.noScaling,
            style: TextStyle(fontSize: extent * 0.62, height: 1.0, fontFamilyFallback: const ['Apple Color Emoji']),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, Palette p) => SizedBox(
        height: _headerHeight,
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(title, style: cw(IOSText.footnote, weight: FontWeight.w600, color: p.muted)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Container(
            height: 36,
            decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Icon(CupertinoIcons.search, size: 17, color: p.muted),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: cw(IOSText.body, color: p.ink),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: tr('搜索表情'),
                    hintStyle: cw(IOSText.body, color: p.muted),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: Icon(CupertinoIcons.xmark_circle_fill, size: 17, color: p.muted),
                ),
            ]),
          ),
        ),
        // Grid
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final extent = (box.maxWidth - _hPad * 2) / _columns;
            if (_query.isNotEmpty) {
              final found = _matches;
              if (found.isEmpty) {
                return Center(child: Text(tr('没有找到表情'), style: cw(IOSText.subheadline, color: p.muted)));
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(_hPad, 8, _hPad, 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _columns, mainAxisExtent: extent),
                itemCount: found.length,
                itemBuilder: (context, i) => _cell(found[i], p, extent),
              );
            }
            // Section start offsets for the tabs.
            var y = 0.0;
            final offsets = <double>[];
            for (final s in _sections) {
              offsets.add(y);
              y += _headerHeight + (s.$3.length / _columns).ceil() * extent;
            }
            _offsets = offsets;
            return CustomScrollView(
              controller: _scroll,
              slivers: [
                for (final s in _sections) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: _hPad),
                    sliver: SliverToBoxAdapter(child: _header(s.$1, p)),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: _hPad),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: _columns, mainAxisExtent: extent),
                      delegate: SliverChildBuilderDelegate((context, i) => _cell(s.$3[i], p, extent), childCount: s.$3.length),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            );
          }),
        ),
        // Group tabs
        DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.cardStroke, width: 0.5))),
          child: SizedBox(
            height: 46,
            child: Row(children: [
              for (var i = 0; i < _sections.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _jumpTo(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: i == _activeTab && _query.isEmpty ? p.track : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_tabIcons[_sections[i].$2], size: 20, color: i == _activeTab && _query.isEmpty ? p.ink : p.muted),
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

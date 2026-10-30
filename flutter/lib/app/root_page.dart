import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components.dart';
import 'entry_editor.dart';
import 'icons.dart';
import 'motion.dart';
import 'pages/categories_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/settings_page.dart';
import 'pages/subscriptions_page.dart';
import 'pages/transactions_page.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Top-level pages, shown as Copilot-style pill tabs under the brand title.
enum CentwisePage {
  dashboard('概览'),
  subscriptions('订阅'),
  categories('分类'),
  transactions('账单');

  const CentwisePage(this.source);
  final String source;
  String get title => tr(source, const {}, 'tab');
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  // Fixed height of the demo / error banner strip inside the floating header.
  static const double _bannerHeight = 26;

  final PageController _pages = PageController();

  /// Set once a pull past 概览's left edge has opened 设置 (so one drag opens it only once).
  bool _pulledSettings = false;
  final ScrollController _tabScroll = ScrollController();
  final List<GlobalKey> _tabKeys = [for (final _ in CentwisePage.values) GlobalKey()];

  /// Set by the magnifier in the header; the bill page consumes it (focus the field, search all dates).
  final ValueNotifier<bool> _searchRequest = ValueNotifier(false);
  CentwisePage _page = CentwisePage.dashboard;
  LedgerStore? _store;
  bool _showingAlert = false;
  bool _showingImport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.read(context);
    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChanged);
      _store = store..addListener(_onStoreChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onStoreChanged());
      WidgetsBinding.instance.addPostFrameCallback((_) => store.scanImportFolder());
    }
  }

  @override
  void dispose() {
    _store?.removeListener(_onStoreChanged);
    _pages.dispose();
    _tabScroll.dispose();
    _searchRequest.dispose();
    super.dispose();
  }

  void _openSearch() {
    _searchRequest.value = true;
    _go(CentwisePage.transactions);
  }

  /// Errors and import previews are presented from here, above whatever sheet is open.
  Future<void> _onStoreChanged() async {
    final store = _store;
    if (store == null || !mounted) return;
    if (store.error != null && !_showingAlert) {
      _showingAlert = true;
      final message = store.error!;
      await showCwAlert(context, tr('操作未完成'), message);
      _showingAlert = false;
      if (store.error == message) store.clearError();
    }
    if (store.pendingImport != null && !_showingImport && mounted) {
      _showingImport = true;
      await showCwSheet<void>(context, (_) => StoreScope(store: store, child: const ImportPreview()));
      _showingImport = false;
      if (store.pendingImport != null) store.cancelImport();
    }
  }

  void _go(CentwisePage page) {
    if (page != _page) HapticFeedback.selectionClick();
    setState(() => _page = page);
    _pages.animateToPage(page.index, duration: IOSMotion.smoothCurve.duration, curve: IOSMotion.smoothCurve);
    _revealTab(page);
  }

  void _revealTab(CentwisePage page) {
    final tab = _tabKeys[page.index].currentContext;
    if (tab != null) Scrollable.ensureVisible(tab, alignment: 0.5, duration: IOSMotion.smoothCurve.duration, curve: IOSMotion.smoothCurve);
  }

  void _newEntry() {
    final store = StoreScope.read(context);
    if (store.loadingFailed) return;
    showCwSheet<void>(context, (_) => StoreScope(store: store, child: const EntryEditor()), guarded: true);
  }

  void _openSettings() {
    final store = StoreScope.read(context);
    showCwSheet<void>(context, (context) => StoreScope(store: store, child: const _SwipeLeftToClose(child: SettingsSheet())));
  }

  /// Swiping right on 概览 (pulling past its left edge, where there is no page) opens 设置.
  bool _onPagesScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollUpdateNotification && n.dragDetails != null && !_pulledSettings && n.metrics.pixels < -56) {
      _pulledSettings = true;
      HapticFeedback.selectionClick();
      _openSettings();
    } else if (n is ScrollEndNotification) {
      _pulledSettings = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);

  Widget _buildPage(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The floating header block (status pad + demo banner + title row + tabs) overlays the pages:
    // pages reserve this much top padding (HeaderInset) and scroll up behind its frosted backdrop.
    final banner = store.isDemo || store.loadingFailed;
    final headerInset = top + (banner ? _bannerHeight : 0) + 56 + 46;
    return Scaffold(
      backgroundColor: p.canvas,
      body: Stack(children: [
        Positioned.fill(
          child: HeaderInset(
            height: headerInset,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onPagesScroll,
              child: PageView(
              controller: _pages,
              onPageChanged: (index) {
                setState(() => _page = CentwisePage.values[index]);
                _revealTab(_page);
              },
              children: [
                DashboardPage(onShowTransactions: () => _go(CentwisePage.transactions), onNewEntry: _newEntry),
                // Same order as CentwisePage: the page index is the tab index.
                const SubscriptionsPage(),
                const CategoriesPage(),
                TransactionsPage(searchRequest: _searchRequest),
              ],
            ),
            ),
          ),
        ),
        // Transition wash under the tabs: softens the frost boundary between the header and the page.
        Positioned(
          left: 0,
          right: 0,
          top: headerInset,
          height: 30,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [p.canvas.withValues(alpha: 0.5), p.canvas.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
        // Floating header, iOS Settings style: over the plain canvas at rest it reads as before, and
        // once pages scroll behind it their content shows through blurred (backdrop filter) + washed.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: ColoredBox(
                color: p.canvas.withValues(alpha: 0.62),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(height: top),
                  if (banner)
                    Container(
                      height: _bannerHeight,
                      width: double.infinity,
                      color: p.track,
                      alignment: Alignment.center,
                      child: Text(
                        store.isDemo ? tr('预览模式 · 初始为演示数据 · 退出后不保存修改') : tr('账本读取失败 · 原文件已保留 · 写入已暂停'),
                        style: cw(12, weight: FontWeight.w500, color: p.muted),
                      ),
                    ),
                  _header(),
                  _tabs(),
                ]),
              ),
            ),
          ),
        ),
        // Bottom controls float over the pages (no solid bar): the period capsule is frosted glass so the
        // content shows through. Page lists end with [bottomControlsClearance] of padding, so the last
        // row can still scroll clear of them.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottom),
          child: Row(children: [
            const SizedBox(width: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                // 订阅 isn't tied to a period, so it has no time capsule.
                child: _page != CentwisePage.subscriptions
                    ? const FittedBox(fit: BoxFit.scaleDown, child: PeriodCapsule())
                    : const SizedBox(height: 44),
              ),
            ),
            const SizedBox(width: 12),
            // On 订阅 the ＋ adds a subscription; everywhere else it records a bill.
            _page == CentwisePage.subscriptions
                ? FloatingCircleButton(icon: 'plus', label: tr('新增订阅'), onTap: store.loadingFailed ? null : () => openSubscription(context))
                : FloatingCircleButton(icon: 'plus', label: tr('记一笔'), onTap: store.loadingFailed ? null : _newEntry),
          ]),
        ),
        ),
      ]),
    );
  }

  Widget _header() {
    final p = Palette.of(context);
    Widget button(String icon, String label, VoidCallback onTap, {double stroke = 1.75, double size = 22}) => Pressable(
          semanticLabel: label,
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Center(child: LIcon(icon, size: size, color: p.ink.withValues(alpha: 0.8), strokeWidth: stroke))),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(children: [
        button('cog', tr('设置与备份'), _openSettings, stroke: 1.75, size: 24),
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Centwise', textAlign: TextAlign.center, style: cw(22, weight: FontWeight.w800, color: p.ink, brand: true)),
          ),
        ),
        button('search', tr('搜索账单'), _openSearch),
      ]),
    );
  }

  Widget _tabs() {
    final p = Palette.of(context);
    // The highlight follows the PageView itself — while swiping between pages or while a tap animates
    // there — so it glides across instead of jumping from tab to tab.
    double position() =>
        _pages.hasClients && _pages.position.haveDimensions ? (_pages.page ?? _page.index.toDouble()) : _page.index.toDouble();
    return SizedBox(
      height: 46,
      child: Center(
        child: SingleChildScrollView(
          controller: _tabScroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: PillTrack(
            count: CentwisePage.values.length,
            listenable: _pages,
            position: position,
            spacing: 6,
            pill: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(99)),
            itemBuilder: (context, i, t) {
              final page = CentwisePage.values[i];
              return Pressable(
                key: _tabKeys[i],
                selected: page == _page,
                onTap: () => _go(page),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  // Same weight for every tab (no width jump); the text turns from grey to white as the black pill arrives.
                  child: Text(page.title, style: cw(15, weight: FontWeight.w600, color: Color.lerp(p.muted, p.onBrand, t))),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// "先核对，再导入" sheet.
class ImportPreview extends StatelessWidget {
  const ImportPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    return SheetScaffold(
      title: tr('导入预览'),
      onLeading: () {
        store.cancelImport();
        Navigator.of(context).pop();
      },
      body: ListView(clipBehavior: Clip.none, padding: const EdgeInsets.all(24), children: [
        Center(child: LIcon('file-down', size: 40, color: p.accent)),
        const SizedBox(height: 14),
        Text(tr('先核对，再导入'), textAlign: TextAlign.center, style: cw(24, weight: FontWeight.w700, color: p.ink)),
        const SizedBox(height: 18),
        CwCard(child: SelectableText(store.importDescription, style: cw(15, color: p.ink, height: 1.5))),
        const SizedBox(height: 14),
        Text(
          store.isDemo
              ? tr('预览模式只替换内存中的账本，退出后不保存。原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。')
              : tr('这是替换导入，不是合并。当前 Centwise 账本会先自动保存一份本地备份；原 Money Pro 文件不会被修改。备份含私人财务数据，请仅保存在可信位置。'),
          style: cw(13, color: p.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        PrimaryBarButton(
          label: tr('确认替换当前账本'),
          onTap: () {
            store.confirmImport();
            if (store.pendingImport == null) Navigator.of(context).pop();
          },
        ),
      ]),
    );
  }
}

/// 设置 closes with a right-to-left swipe (the reverse of the swipe that opens it from 概览), and
/// with a pull down: its list fills the sheet, so a downward drag would otherwise only bounce the
/// list. Pulling the list down past its top closes the sheet instead.
class _SwipeLeftToClose extends StatefulWidget {
  const _SwipeLeftToClose({required this.child});
  final Widget child;

  @override
  State<_SwipeLeftToClose> createState() => _SwipeLeftToCloseState();
}

class _SwipeLeftToCloseState extends State<_SwipeLeftToClose> {
  double _dx = 0;
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    HapticFeedback.selectionClick();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.dragDetails != null && n.metrics.pixels < -64) _close();
          return false;
        },
        child: GestureDetector(
          onHorizontalDragStart: (_) => _dx = 0,
          onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
          onHorizontalDragEnd: (d) {
            if (_dx < -70 || (d.primaryVelocity ?? 0) < -400) _close();
          },
          child: widget.child,
        ),
      );
}

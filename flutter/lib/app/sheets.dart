import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'components.dart';
import 'icons.dart';
import 'lucide_icons.dart';
import 'motion.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Opens [builder] as a Copilot-style sheet: rounded top, grabber, canvas background, near full height.
///
/// With [guarded], swiping the sheet down asks the route to pop (Navigator.maybePop) instead of closing
/// it outright, so a PopScope inside — e.g. "放弃本次修改？" in the entry editor — can keep it open.
/// Flutter's own drag-to-dismiss pops directly and would skip that check.
/// How many [showCwSheet] sheets are open.
final ValueNotifier<int> openSheets = ValueNotifier(0);

/// [height] makes a shorter sheet (in points, capped at the usual near-full height) for short content,
/// e.g. one category's subcategory list.
Future<T?> showCwSheet<T>(BuildContext context, WidgetBuilder builder, {bool guarded = false, double? height}) async {
  final p = Palette.of(context);
  openSheets.value++;
  try {
    return await _presentSheet<T>(context, p, builder, guarded, height);
  } finally {
    openSheets.value--;
  }
}

Future<T?> _presentSheet<T>(BuildContext context, Palette p, WidgetBuilder builder, bool guarded, double? height) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: !guarded,
    // The sheet is frosted glass (see the builder), so the route itself paints nothing.
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x40000000),
    // iOS 26 sheets have large, soft top corners.
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    clipBehavior: Clip.antiAlias,
    // iOS sheets rise and fall on a smooth (no-bounce) spring.
    sheetAnimationStyle: AnimationStyle(
      duration: IOSMotion.smoothCurve.duration,
      curve: IOSMotion.smoothCurve,
      reverseDuration: IOSMotion.smoothCurve.duration,
      reverseCurve: IOSMotion.smoothCurve.flipped,
    ),
    // iOS 26 sheets are glass: the page behind shows through, heavily blurred, under a milky layer of the
    // canvas colour; the cards and controls inside stay solid. Built here (not via backgroundColor) so it
    // follows a theme change made while the sheet is open.
    builder: (context) {
      final content = _glass(context, builder(context));
      final sheet = guarded ? _DragToClose(child: content) : content;
      if (height == null) return FractionallySizedBox(heightFactor: 0.94, child: sheet);
      return LayoutBuilder(
        builder: (context, box) => SizedBox(height: height < box.maxHeight * 0.94 ? height : box.maxHeight * 0.94, child: sheet),
      );
    },
  );
}

/// The iOS 26 glass sheet surface: the page behind shows through, heavily blurred, under a milky layer
/// of the canvas colour; the cards and controls inside stay solid. Built in the route builder (not via
/// backgroundColor) so it follows a theme change made while the sheet is open.
Widget _glass(BuildContext context, Widget child) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  // Light mode: after the blur the backdrop is lifted 45 % toward white (so the dimmed page behind
  // doesn't read as grey), then a near-white milk layer goes on top.
  const lift = 0.45;
  return BackdropFilter(
    filter: dark
        ? ImageFilter.blur(sigmaX: 40, sigmaY: 40)
        : ImageFilter.compose(
            outer: const ColorFilter.matrix([
              1 - lift, 0, 0, 0, 255 * lift, //
              0, 1 - lift, 0, 0, 255 * lift, //
              0, 0, 1 - lift, 0, 255 * lift, //
              0, 0, 0, 1, 0,
            ]),
            inner: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          ),
    child: ColoredBox(
      color: dark ? Palette.of(context).canvas.withValues(alpha: 0.78) : const Color(0xFFF9F9FB).withValues(alpha: 0.7),
      child: child,
    ),
  );
}

/// A short list of choices as a small glass sheet sized to its content, laid out like an iOS Settings
/// group: a centred title with a glass ✕, then one inset-grouped card of [FormRow]s (icon tile, label,
/// a checkmark on the current choice). Returns what [rows] pop with.
Future<T?> showOptionSheet<T>(BuildContext context, {required String title, required List<Widget> Function(BuildContext) rows}) {
  openSheets.value++;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: const Color(0x40000000),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: AnimationStyle(
      duration: IOSMotion.smoothCurve.duration,
      curve: IOSMotion.smoothCurve,
      reverseDuration: IOSMotion.smoothCurve.duration,
      reverseCurve: IOSMotion.smoothCurve.flipped,
    ),
    builder: (context) {
      final p = Palette.of(context);
      return _glass(
        context,
        SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SizedBox(
                height: 44,
                child: Stack(alignment: Alignment.center, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.headline, weight: FontWeight.w600, color: p.ink)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GlassBarButton(icon: 'x', semanticLabel: tr('取消'), onTap: () => Navigator.of(context).maybePop()),
                  ),
                ]),
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), child: FormSection(children: rows(context))),
          ]),
        ),
      );
    },
  ).whenComplete(() => openSheets.value--);
}

/// Swipe-down for a guarded sheet: the sheet follows the finger, and on release either springs back or
/// asks the route to close (which a PopScope may turn into a confirmation).
class _DragToClose extends StatefulWidget {
  const _DragToClose({required this.child});
  final Widget child;

  @override
  State<_DragToClose> createState() => _DragToCloseState();
}

class _DragToCloseState extends State<_DragToClose> with SingleTickerProviderStateMixin {
  late final AnimationController _offset =
      AnimationController(vsync: this, lowerBound: 0, upperBound: 4000, value: 0);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final height = context.size?.height ?? 600;
    final close = velocity > 700 || _offset.value > height * 0.25;
    // Spring back with the finger's velocity; when closing, the route's own sheet animation takes over.
    IOSMotion.animate(_offset, 0, spring: IOSMotion.snappy, velocity: close ? 0 : velocity);
    if (close) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) => _offset.value = (_offset.value + details.delta.dy).clamp(0.0, 4000.0).toDouble(),
      onVerticalDragEnd: _end,
      onVerticalDragCancel: () => IOSMotion.animate(_offset, 0, spring: IOSMotion.snappy),
      child: AnimatedBuilder(
        animation: _offset,
        child: widget.child,
        builder: (context, child) => Transform.translate(offset: Offset(0, _offset.value), child: child),
      ),
    );
  }
}

/// "放弃本次修改？" — returns true when the user chooses to discard.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final result = await showIOSAlert<bool>(
    context,
    title: tr('放弃本次修改？'),
    message: tr('已输入的内容不会保存。'),
    actions: [
      IOSAlertAction(label: tr('继续编辑'), value: false, prominent: true),
      IOSAlertAction(label: tr('放弃修改'), value: true, destructive: true),
    ],
  );
  return result ?? false;
}

/// One button of an [showIOSAlert] alert.
class IOSAlertAction<T> {
  const IOSAlertAction({required this.label, required this.value, this.destructive = false, this.prominent = false});
  final String label;
  final T value;

  /// Red label, for actions that throw something away.
  final bool destructive;

  /// Filled black capsule, for the one action the alert recommends.
  final bool prominent;
}

/// An alert in the iOS 26 style: a large-radius glass card, a left-aligned semibold 17 pt title and a
/// grey 15 pt message, and the actions as capsules side by side (stacked when there are more than two
/// or a label is long) — the recommended one filled, the rest on grey glass. It scales in from slightly larger, like UIKit's, and the backdrop dims.
/// Tapping outside does nothing, as on iOS; the result is the tapped action's value.
Future<T?> showIOSAlert<T>(BuildContext context,
    {required String title, String? message, required List<IOSAlertAction<T>> actions}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, __) => _IOSAlert<T>(title: title, message: message, actions: actions),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: IOSMotion.bouncyCurve, reverseCurve: Curves.easeOut);
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: animation.status == AnimationStatus.reverse
            ? child
            : ScaleTransition(scale: Tween(begin: 1.12, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _IOSAlert<T> extends StatelessWidget {
  const _IOSAlert({super.key, required this.title, this.message, required this.actions});
  final String title;
  final String? message;
  final List<IOSAlertAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stacked = actions.length > 2 || actions.any((a) => a.label.characters.length > 6);

    Widget button(IOSAlertAction<T> a) => Pressable(
          semanticLabel: a.label,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(a.value);
          },
          // Same capsules as the sheets' main buttons (保存这笔支出): 52 pt, black when recommended,
          // the system grey track otherwise.
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: a.prominent ? p.brand : p.track,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(a.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cw(IOSText.body,
                    weight: FontWeight.w600, color: a.prominent ? p.onBrand : (a.destructive ? p.over : p.ink))),
          ),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              // The sheets' look: 32 pt corners and their bright frosted surface, so an alert reads as
              // part of the same family rather than a grey system box.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.5 : 0.14), blurRadius: 36, offset: const Offset(0, 12))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    color: dark ? p.card.withValues(alpha: 0.92) : const Color(0xFFF9F9FB).withValues(alpha: 0.94),
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      // iOS 26 alerts read like a short note: title and message flush left.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(title, style: cw(IOSText.headline, weight: FontWeight.w600, color: p.ink)),
                      ),
                      if (message != null) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(message!, style: cw(IOSText.subheadline, color: p.muted, height: 1.35)),
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (stacked)
                        Column(children: [
                          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 8), button(actions[i])]
                        ])
                      else
                        Row(children: [
                          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: button(actions[i]))]
                        ]),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet chrome: grabber, then [leading] · small spaced title · [trailing].
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leadingLabel,
    this.onLeading,
    this.trailingLabel,
    this.onTrailing,
    this.bottom,
    this.titleWidget,
    this.largeTitle = false,
    this.closeButton = true,
    this.contentUnderBar = false,
  });

  /// The body starts at the sheet's top edge instead of below the bar, so its first rows sit beside
  /// the bar buttons (记一笔: the amount rises next to the ✕ rather than below an empty bar).
  final bool contentUnderBar;

  /// iOS large title: [body] starts with the title itself (see [SheetLargeTitle]); the bar stays
  /// empty and clear until it scrolls away, then the small centred title fades into the frosted bar.
  final bool largeTitle;

  /// false: no ✕ / 完成 in the bar (the sheet still closes by swiping down or tapping outside).
  final bool closeButton;

  final String title;

  /// Shown at the left of the bar instead of the centred [title] (e.g. the 支出 / 收入 switch).
  final Widget? titleWidget;
  final Widget body;
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final String? trailingLabel;
  final VoidCallback? onTrailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dismiss = onLeading ?? () => Navigator.of(context).maybePop();
    final label = leadingLabel ?? tr('取消');
    // iOS 26 sheet bar: the leading text becomes a round glass button — ‹ for 返回, ✕ for 取消 / 完成.
    // With no other action the ✕ sits top-right (完成 as a glass capsule there); with an action such as
    // 保存 the ✕ moves left and the action is a glass capsule on the right.
    final isBack = label == tr('返回');
    final isDone = label == tr('完成');
    Widget? left;
    Widget? right;
    if (isBack) {
      left = GlassBarButton(icon: 'chevron-left', semanticLabel: label, onTap: dismiss);
    } else if (trailingLabel == null) {
      right = isDone
          ? GlassBarButton(label: label, onTap: dismiss)
          : GlassBarButton(icon: 'x', semanticLabel: label, onTap: dismiss);
    } else {
      left = GlassBarButton(icon: 'x', semanticLabel: label, onTap: dismiss);
    }
    if (trailingLabel != null) right = GlassBarButton(label: trailingLabel, onTap: onTrailing, emphasized: true);
    if (!closeButton) {
      if (!isBack) left = null;
      if (trailingLabel == null) right = null;
    }

    // No grabber (iOS 26 sheets don't show one with a glass ✕); swipe down still closes.
    final bar = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: SizedBox(
          height: 44,
          child: Stack(alignment: Alignment.center, children: [
            if (titleWidget == null && !largeTitle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 96),
                // A title that changes in place (a push inside the sheet) cross-fades, as in a nav bar.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(title,
                      key: ValueKey(title),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.headline, weight: FontWeight.w600, color: p.ink)),
                ),
              )
            else if (titleWidget != null)
              Semantics(header: true, label: title, child: Align(alignment: Alignment.centerLeft, child: titleWidget)),
            if (left != null && titleWidget == null) Align(alignment: Alignment.centerLeft, child: left),
            if (right != null) Align(alignment: Alignment.centerRight, child: right),
          ]),
        ),
      );
    // The bottom controls float over the body (the form scrolls behind their frosted backdrop).
    // They are painted inside ScrollEdgeEffect, before the bar: on iPhone the bar's ✕ is a native
    // view, and a backdrop blur painted after a native view can't see the content beneath it.
    return ScrollEdgeEffect(
      bar: bar,
      largeTitle: largeTitle ? title : null,
      contentUnderBar: contentUnderBar,
      bottom: bottom,
      child: body,
    );
  }
}

/// iOS 26 navigation-bar button: a 44 pt glass circle with an SF-style glyph (✕, ‹), or a glass
/// capsule with a label (编辑 / 保存). White glass with a hairline rim and a soft shadow, like the
/// buttons at the top of iOS Settings; disabled when [onTap] is null.
class GlassBarButton extends StatelessWidget {
  const GlassBarButton({super.key, this.icon, this.label, this.semanticLabel, this.onTap, this.emphasized = false})
      : assert(icon != null || label != null);
  final String? icon;
  final String? label;
  final String? semanticLabel;
  final VoidCallback? onTap;

  /// Semibold label (the sheet's main action).
  final bool emphasized;


  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onTap != null;
    final color = enabled ? p.ink : p.muted;
    // Drawn by Flutter on every platform. The native iOS 26 glass button (cupertino_native_better
    // CNButton) was tried here, but on iPhone its SwiftUI glass came out larger than its 44 pt frame and
    // pinned to the sheet's top edge instead of centring on the title row.
    return Pressable(
      semanticLabel: semanticLabel ?? label,
      onTap: onTap,
      // Liquid Glass: blurred, neutral backdrop with a light-catching rim and a soft floating shadow.
      child: LiquidGlass(
        radius: 22,
        circle: icon != null,
        child: Container(
        height: 44,
        width: icon != null ? 44 : null,
        padding: icon != null ? null : const EdgeInsets.symmetric(horizontal: 18),
        // widthFactor 1: centred vertically but only as wide as its content (a capsule hugs its label).
        child: Center(
          widthFactor: 1,
          child: icon != null
              ? LIcon(icon!, size: 19, color: color, strokeWidth: 2.5)
              : Text(label!, style: cw(IOSText.body, weight: emphasized ? FontWeight.w600 : FontWeight.w500, color: color)),
        ),
      ),
      ),
    );
  }
}

/// The big left-aligned title that opens a large-title [SheetScaffold] body (30 pt bold). It is an
/// ordinary first row: it scrolls up under the frosted bar, which blurs it, and the bar then shows
/// the small title. The list should use [topPadding] as its top padding.
class SheetLargeTitle extends StatelessWidget {
  const SheetLargeTitle(this.title, {super.key});
  final String title;

  static const double fontSize = 30;
  static const double topPadding = 40;
  static const double bottomGap = 22;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, bottomGap),
      child: Semantics(
        header: true,
        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(fontSize, weight: FontWeight.w700, color: Palette.of(context).ink, height: 1.2)),
      ),
    );
  }
}

/// iOS 26 sheet bar over scrolling content: the content scrolls up *under* the bar instead of being
/// cut off below it, and once it has moved the bar turns into frosted glass — the content behind it
/// blurred and washed toward the sheet colour, with a hairline at its lower edge (as in Settings).
/// At rest the bar is clear. Scrollables in [child] should use `clipBehavior: Clip.none` so their
/// rows can paint up into the bar area; the bottom edge is still clipped.
class ScrollEdgeEffect extends StatefulWidget {
  const ScrollEdgeEffect({super.key, required this.bar, required this.child, this.largeTitle, this.contentUnderBar = false, this.bottom});
  final Widget bar;
  final Widget child;

  /// See [SheetScaffold.contentUnderBar].
  final bool contentUnderBar;

  /// Controls pinned to the bottom edge, floating over [child].
  final Widget? bottom;

  /// Large-title mode: the content starts at the very top and its first row is a [SheetLargeTitle].
  /// It scrolls away under the frosted bar like any row; once it is mostly gone this small title
  /// drops into the bar from above.
  final String? largeTitle;

  /// Scroll distance at which the bar takes over from the large title.
  static const double largeTitleCollapseAt = 30;

  /// 16 top + 44 buttons + 8 bottom.
  static const double barHeight = 68;

  @override
  State<ScrollEdgeEffect> createState() => _ScrollEdgeEffectState();
}

class _ScrollEdgeEffectState extends State<ScrollEdgeEffect> {
  /// 0 = at the top, 1 = scrolled at least 16 pt (bar fully frosted).
  final ValueNotifier<double> _amount = ValueNotifier(0);

  /// Whether the large title has scrolled away and the bar title is showing (large-title mode).
  final ValueNotifier<bool> _collapsed = ValueNotifier(false);

  @override
  void dispose() {
    _amount.dispose();
    _collapsed.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // Only the outermost vertical scroll view drives it (not a horizontal row inside).
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      final px = n.metrics.pixels - n.metrics.minScrollExtent;
      final start = widget.largeTitle != null ? ScrollEdgeEffect.largeTitleCollapseAt : 0.0;
      _amount.value = ((px - start) / 16).clamp(0.0, 1.0);
      _collapsed.value = px > ScrollEdgeEffect.largeTitleCollapseAt;
    }
    return false;
  }

  /// The small bar title at progress [t]: 0 = hidden just above the bar, 1 = in place.
  Widget _barTitle(BuildContext context, double t) {
    return Positioned(
      left: 96,
      right: 96,
      top: 16,
      height: 44,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - t)),
          child: Center(
            child: Text(widget.largeTitle!,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.headline, weight: FontWeight.w600, color: Palette.of(context).ink)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const h = ScrollEdgeEffect.barHeight;
    final large = widget.largeTitle != null;
    final top = large || widget.contentUnderBar ? 0.0 : h;
    return Stack(children: [
      Positioned.fill(
        top: top,
        child: ClipRect(
          clipper: _ExtendUpClipper(top),
          child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
        ),
      ),
      // Frosted bar background, faded in as the content starts to pass under it.
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        height: h,
        child: IgnorePointer(
          child: ValueListenableBuilder<double>(
            valueListenable: _amount,
            builder: (context, amount, _) {
              if (amount <= 0) return const SizedBox.shrink();
              // No Opacity wrapper here: a BackdropFilter inside an Opacity layer only sees that
              // (empty) layer, so the blur silently does nothing. The effect is ramped in through
              // the blur radius and the tint instead.
              final sat = 1 + 0.5 * amount; // Liquid Glass lifts the colour of what's beneath
              const lr = 0.2126, lg = 0.7152, lb = 0.0722;
              final saturate = ColorFilter.matrix([
                lr * (1 - sat) + sat, lg * (1 - sat), lb * (1 - sat), 0, 0, //
                lr * (1 - sat), lg * (1 - sat) + sat, lb * (1 - sat), 0, 0, //
                lr * (1 - sat), lg * (1 - sat), lb * (1 - sat) + sat, 0, 0, //
                0, 0, 0, 1, 0,
              ]);
              return ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.compose(outer: saturate, inner: ImageFilter.blur(sigmaX: 22 * amount, sigmaY: 22 * amount)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Light frost, brighter at the top like light caught in the glass.
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: dark
                            ? [p.canvas.withValues(alpha: 0.62 * amount), p.canvas.withValues(alpha: 0.48 * amount)]
                            : [Colors.white.withValues(alpha: 0.62 * amount), const Color(0xFFF7F7F9).withValues(alpha: 0.42 * amount)],
                      ),
                      border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: (dark ? 0.35 : 0.08) * amount), width: 0.5)),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      // Large-title mode: the big title scrolls away with the list (blurred under the frosted bar);
      // once it has gone, the small title drops into the bar from above.
      if (large)
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _collapsed,
              builder: (context, collapsed, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: collapsed ? 1 : 0),
                duration: Duration(milliseconds: collapsed ? 380 : 220),
                curve: collapsed ? Curves.easeOutBack : Curves.easeIn,
                builder: (context, t, _) => Stack(children: [_barTitle(context, t)]),
              ),
            ),
          ),
        ),
      if (widget.bottom != null) Positioned(left: 0, right: 0, bottom: 0, child: widget.bottom!),
      Positioned(left: 0, right: 0, top: 0, height: h, child: widget.bar),
    ]);
  }
}

/// Clips to the child's box, extended [up] points above it (so rows can slide under the sheet bar).
class _ExtendUpClipper extends CustomClipper<Rect> {
  const _ExtendUpClipper(this.up);
  final double up;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -up, size.width, size.height);

  @override
  bool shouldReclip(covariant _ExtendUpClipper old) => old.up != up;
}

/// iOS-style alert with one dismiss button.
Future<void> showCwAlert(BuildContext context, String title, String message) {
  return showIOSAlert<void>(context, title: title, message: message, actions: [IOSAlertAction(label: tr('知道了'), value: null, prominent: true)]);
}

/// iOS-style confirmation (action sheet) with a destructive action. Returns true when confirmed.
Future<bool> confirmDestructive(BuildContext context, String message, String action) async {
  final result = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (context) => CupertinoActionSheet(
      message: Text(message),
      actions: [
        CupertinoActionSheetAction(isDestructiveAction: true, onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
      ],
      cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('取消'))),
    ),
  );
  return result ?? false;
}

/// iOS inset-grouped section (Settings style): small grey header, a white card of rows separated by
/// hairlines inset to the text, small grey footer.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.title, required this.children, this.footer});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 7),
          child: Text(title!, style: cw(IOSText.footnote, color: p.muted)),
        ),
      // iOS 26 Settings: inset group, 16 pt content inset. Same card radius as the home page's
      // cards, so every white block in the app shares one corner.
      CwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Padding(
                // The separator starts where the row's text starts, past its icon tile.
                padding: EdgeInsets.only(left: children[i] is FormRow && (children[i] as FormRow).icon != null ? FormRow.textInset : 0),
                child: Divider(height: 0.5, thickness: 0.5, color: p.cardStroke),
              ),
            children[i],
          ]
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
          child: Text(footer!, style: cw(IOSText.footnote, color: p.muted, height: 1.35)),
        ),
    ]);
  }
}

/// One row in a [FormSection], like a row in iOS Settings: an optional icon on a small grey rounded
/// tile, a 17 pt label, a trailing value and/or a disclosure chevron; tappable when [onTap] is set.
class FormRow extends StatelessWidget {
  const FormRow({super.key, this.icon, required this.label, this.trailing, this.onTap, this.destructive = false, this.chevron = false});

  /// Where the label starts when the row has an icon tile (tile 29 + gap 15, as in iOS Settings, where
  /// text sits 60 pt from the group's edge); separators inset to it.
  static const double textInset = 44;

  /// iOS Settings row height.
  static const double minHeight = 50;
  final String? icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final color = destructive ? p.over : (onTap != null && trailing == null && !chevron ? p.accent : p.ink);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Row(children: [
        if (icon != null) ...[
          FormIconTile(icon!, color: destructive ? p.over : null),
          const SizedBox(width: FormRow.textInset - FormIconTile.size),
        ],
        Expanded(child: Text(label, style: cw(IOSText.body, weight: FontWeight.w400, color: color))),
        if (trailing != null)
          DefaultTextStyle.merge(style: cw(IOSText.body, weight: FontWeight.w400, color: p.muted), child: trailing!),
        if (chevron) ...[const SizedBox(width: 8), LIcon('chevron-right', size: 14, color: p.muted.withValues(alpha: 0.6))],
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

/// The rounded square icon tile at the start of an iOS Settings row, modelled on iOS 26 Settings
/// (measured from a device capture): 28 pt squircle, a soft top-to-bottom gradient in the system
/// colour, a hairline light rim that is brightest along the top edge, a faint contact shadow, and a
/// large off-white line glyph (~2/3 of the tile) with a whisper of shadow so it reads crisply.
/// Blue is left out to keep with the app's monochrome brand.
class FormIconTile extends StatelessWidget {
  const FormIconTile(this.icon, {super.key, this.color});
  static const double size = 29;
  final String icon;

  /// Overrides the tile colour (e.g. red for a destructive row).
  final Color? color;

  // Apple's iOS 26 system colours (light), the ones the Settings icons are built on. Blue is left out
  // to keep with the app's monochrome brand.
  static const _orange = Color(0xFFFF8D28);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF383C);
  static const _purple = Color(0xFFCB30E0);
  static const _pink = Color(0xFFFF2D55);
  static const _yellow = Color(0xFFFFCC00);
  static const _brown = Color(0xFFAC7F5E);
  static const _gray = Color(0xFF8E8E93);
  static const _black = Color(0xFF1C1C1E);

  /// Row icon (Lucide name) → tile colour.
  static const Map<String, Color> _colors = {
    'book-open': _orange,
    'check': _green,
    'receipt': _gray,
    'banknote': _green,
    'coins': _green,
    'cloud-off': _gray,
    'cloud': _gray,
    'cloud-check': _green,
    'upload': _orange,
    'download': _purple,
    'info': _gray,
    'layout-grid': _purple,
    'sun-moon': _black,
    'languages': _gray,
    'refresh-cw': _gray,
    'credit-card': _orange,
    'wallet': _orange,
    'piggy-bank': _pink,
    'archive': _brown,
    'equal': _gray,
    'trash': _red,
    'log-out': _red,
    'chart-pie': _purple,
    'folder-search': _yellow,
    'shield-check': _green,
    'circle-user-round': _gray,
    // Bill-type filter (账单 → 筛选).
    'kind-all': _gray,
    'kind-expense': _orange,
    'kind-income': _green,
    'kind-transfer': _purple,
    'kind-adjustment': _brown,
  };

  /// Glyphs in the manner of the SF Symbols Settings uses: mostly solid shapes with details knocked
  /// out in the tile colour ({bg}), a few line glyphs where the symbol itself is a line. 24-unit grid;
  /// {fg} is the glyph colour. Names without an entry fall back to the Lucide line icon.
  static const Map<String, String> _glyphs = {
    // book.fill
    'book-open': '<path fill="{fg}" d="M1.8 5.4c0-.8.7-1.4 1.5-1.3 3 .3 5.7 1.2 7.9 2.7v13.6c-2.2-1.4-4.9-2.3-7.9-2.6-.8-.1-1.5-.7-1.5-1.5Z"/>'
        '<path fill="{fg}" d="M22.2 5.4c0-.8-.7-1.4-1.5-1.3-3 .3-5.7 1.2-7.9 2.7v13.6c2.2-1.4 4.9-2.3 7.9-2.6.8-.1 1.5-.7 1.5-1.5Z"/>',
    // checkmark (heavy)
    'check': '<path fill="none" stroke="{fg}" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" d="M4.8 12.6 9.6 17.4 19.2 7"/>',
    // doc.text.fill
    'receipt': '<path fill="{fg}" d="M6.2 1.8h7.6l6.4 6.4v11.6a2.4 2.4 0 0 1-2.4 2.4H6.2a2.4 2.4 0 0 1-2.4-2.4V4.2a2.4 2.4 0 0 1 2.4-2.4Z"/>'
        '<path fill="none" stroke="{bg}" stroke-width="1.3" stroke-linejoin="round" d="M13.6 2v4.4a1.8 1.8 0 0 0 1.8 1.8H20"/>'
        '<path fill="none" stroke="{bg}" stroke-width="1.7" stroke-linecap="round" d="M7.8 12.2h8.4M7.8 15.6h8.4M7.8 19h5.2"/>',
    // Two stacked coins, solid like an SF Symbol: the back coin peeks out lower right; the front
    // coin is cut from it by a tile-coloured gap and carries an inner rim.
    'coins': '<circle cx="15.2" cy="15.2" r="6.8" fill="{fg}"/>'
        '<circle cx="9.4" cy="9.4" r="8.3" fill="{bg}"/>'
        '<circle cx="9.4" cy="9.4" r="7" fill="{fg}"/>'
        '<circle cx="9.4" cy="9.4" r="4.4" fill="none" stroke="{bg}" stroke-width="1.2"/>',
    // yensign.circle.fill
    'banknote': '<circle cx="12" cy="12" r="10.2" fill="{fg}"/>'
        '<path fill="none" stroke="{bg}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M8.4 6.6 12 11.6l3.6-5M12 11.6v6.2M8.8 12.4h6.4M8.8 15.2h6.4"/>',
    // icloud.fill
    'cloud': '<path fill="{fg}" d="M6.6 19.8a5.2 5.2 0 0 1-.7-10.35 6.8 6.8 0 0 1 13 .45 4.95 4.95 0 0 1-.4 9.9Z"/>',
    // icloud.slash.fill
    'cloud-off': '<path fill="{fg}" d="M6.6 19.8a5.2 5.2 0 0 1-.7-10.35 6.8 6.8 0 0 1 13 .45 4.95 4.95 0 0 1-.4 9.9Z"/>'
        '<path stroke="{bg}" stroke-width="4.2" stroke-linecap="round" d="M3.6 2.8 20.4 21.2"/>'
        '<path stroke="{fg}" stroke-width="1.9" stroke-linecap="round" d="M3.6 2.8 20.4 21.2"/>',
    // checkmark.icloud.fill
    'cloud-check': '<path fill="{fg}" d="M6.6 19.8a5.2 5.2 0 0 1-.7-10.35 6.8 6.8 0 0 1 13 .45 4.95 4.95 0 0 1-.4 9.9Z"/>'
        '<path fill="none" stroke="{bg}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M8.8 14.2l2.2 2.2 4.2-4.6"/>',
    // square.and.arrow.up
    'upload': '<path fill="none" stroke="{fg}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" d="M8.4 9.4H7a2 2 0 0 0-2 2v8.2a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8.2a2 2 0 0 0-2-2h-1.4M12 15V2.6M8.2 6.2 12 2.4l3.8 3.8"/>',
    // square.and.arrow.down
    'download': '<path fill="none" stroke="{fg}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" d="M8.4 7.4H7a2 2 0 0 0-2 2v10.2a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V9.4a2 2 0 0 0-2-2h-1.4M12 2.4v12.4M8.2 11.2 12 15l3.8-3.8"/>',
    // info.circle.fill
    'info': '<circle cx="12" cy="12" r="10.2" fill="{fg}"/>'
        '<path stroke="{bg}" stroke-width="2.3" stroke-linecap="round" d="M12 11v6"/><circle cx="12" cy="7.4" r="1.45" fill="{bg}"/>',
    // square.grid.2x2.fill
    'layout-grid': '<rect x="2.6" y="2.6" width="8.2" height="8.2" rx="2.3" fill="{fg}"/><rect x="13.2" y="2.6" width="8.2" height="8.2" rx="2.3" fill="{fg}"/>'
        '<rect x="2.6" y="13.2" width="8.2" height="8.2" rx="2.3" fill="{fg}"/><rect x="13.2" y="13.2" width="8.2" height="8.2" rx="2.3" fill="{fg}"/>',
    // circle.lefthalf.filled
    'sun-moon': '<circle cx="12" cy="12" r="9" fill="none" stroke="{fg}" stroke-width="2.2"/><path fill="{fg}" d="M12 3a9 9 0 0 0 0 18Z"/>',
    // globe
    'languages': '<g fill="none" stroke="{fg}" stroke-width="1.8"><circle cx="12" cy="12" r="9.6"/><ellipse cx="12" cy="12" rx="4.2" ry="9.6"/>'
        '<path d="M2.6 12h18.8M4.2 6.8h15.6M4.2 17.2h15.6"/></g>',
    // arrow.clockwise
    // arrow.triangle.2.circlepath: two arcs chasing each other, solid arrowheads.
    'refresh-cw': '<path fill="none" stroke="{fg}" stroke-width="2.1" stroke-linecap="round" d="M5.2 11.2A7 7 0 0 1 17.6 7.6"/>'
        '<path fill="{fg}" stroke="{fg}" stroke-width="0.8" stroke-linejoin="round" d="M19.4 3.6v5.2h-5.2Z"/>'
        '<path fill="none" stroke="{fg}" stroke-width="2.1" stroke-linecap="round" d="M18.8 12.8A7 7 0 0 1 6.4 16.4"/>'
        '<path fill="{fg}" stroke="{fg}" stroke-width="0.8" stroke-linejoin="round" d="M4.6 20.4v-5.2h5.2Z"/>',
    // creditcard.fill
    'credit-card': '<rect x="1.8" y="4.4" width="20.4" height="15.2" rx="2.6" fill="{fg}"/><rect x="1.8" y="7.8" width="20.4" height="3" fill="{bg}"/>'
        '<rect x="4.6" y="14.4" width="5.2" height="2.2" rx="1.1" fill="{bg}"/>',
    'wallet': '<rect x="1.8" y="4.4" width="20.4" height="15.2" rx="2.6" fill="{fg}"/><rect x="1.8" y="7.8" width="20.4" height="3" fill="{bg}"/>'
        '<rect x="4.6" y="14.4" width="5.2" height="2.2" rx="1.1" fill="{bg}"/>',
    // banknote.fill (savings)
    'piggy-bank': '<rect x="1.6" y="5.2" width="20.8" height="13.6" rx="2.6" fill="{fg}"/><circle cx="12" cy="12" r="3.4" fill="{bg}"/>'
        '<circle cx="5.8" cy="12" r="1.1" fill="{bg}"/><circle cx="18.2" cy="12" r="1.1" fill="{bg}"/>',
    // archivebox.fill
    'archive': '<rect x="1.8" y="3" width="20.4" height="5.4" rx="1.6" fill="{fg}"/><path fill="{fg}" d="M3.4 9.8h17.2v9.4a2 2 0 0 1-2 2H5.4a2 2 0 0 1-2-2Z"/>'
        '<path stroke="{bg}" stroke-width="2" stroke-linecap="round" d="M9.4 13.4h5.2"/>',
    // equal
    'equal': '<path stroke="{fg}" stroke-width="2.8" stroke-linecap="round" d="M5.6 9h12.8M5.6 15h12.8"/>',
    // trash.fill
    'trash': '<path fill="none" stroke="{fg}" stroke-width="2.1" stroke-linecap="round" d="M3.6 5.8h16.8M9 5.6V4.2A1.6 1.6 0 0 1 10.6 2.6h2.8A1.6 1.6 0 0 1 15 4.2v1.4"/>'
        '<path fill="{fg}" d="M5.2 8h13.6l-1 12a2 2 0 0 1-2 1.8H8.2a2 2 0 0 1-2-1.8Z"/>',
    // chart.pie.fill
    'chart-pie': '<path fill="{fg}" d="M10.8 3.2A9.2 9.2 0 1 0 20.8 13.2h-10Z"/><path fill="{fg}" d="M12.8 1.6v9.6h9.6a9.6 9.6 0 0 0-9.6-9.6Z"/>',
    // folder.fill
    'folder-search': '<path fill="{fg}" d="M1.8 6.4A2.6 2.6 0 0 1 4.4 3.8h4.5a2.2 2.2 0 0 1 1.6.7l1.6 1.8h7.5a2.6 2.6 0 0 1 2.6 2.6v9.7a2.6 2.6 0 0 1-2.6 2.6H4.4a2.6 2.6 0 0 1-2.6-2.6Z"/>',
    // checkmark.shield.fill
    'shield-check': '<path fill="{fg}" d="M12 1.8 3.8 4.9v6.4c0 5 3.4 9.1 8.2 10.9 4.8-1.8 8.2-5.9 8.2-10.9V4.9Z"/>'
        '<path fill="none" stroke="{bg}" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" d="M8.2 12.2l2.6 2.6 5-5.4"/>',
    // arrow.up.right (heavy)
    'kind-expense': '<path fill="none" stroke="{fg}" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" d="M6.6 17.4 17.2 6.8M8.6 6.6h8.8v8.8"/>',
    // arrow.down.left (heavy)
    'kind-income': '<path fill="none" stroke="{fg}" stroke-width="2.7" stroke-linecap="round" stroke-linejoin="round" d="M17.4 6.6 6.8 17.2M15.4 17.4H6.6V8.6"/>',
    // arrow.left.arrow.right (heavy)
    'kind-transfer': '<path fill="none" stroke="{fg}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" d="M4 8h15.2M15.6 4.2 19.4 8l-3.8 3.8M20 16H4.8M8.4 12.2 4.6 16l3.8 3.8"/>',
    // person.crop.circle.fill
    'circle-user-round': '<circle cx="12" cy="12" r="10.2" fill="{fg}"/><circle cx="12" cy="9.4" r="3.5" fill="{bg}"/>'
        '<path fill="{bg}" d="M5.3 18.6a7.8 7.8 0 0 1 13.4 0A10.2 10.2 0 0 1 12 22.2a10.2 10.2 0 0 1-6.7-3.6Z"/>',
  };

  /// The real SF Symbols for each row, per Apple's HIG ("use SF Symbols … consistent, highly
  /// configurable"); see [_sfImage]. Names as in the SF Symbols app.
  static const Map<String, String> _sfSymbols = {
    'book-open': 'book.fill',
    'receipt': 'doc.text.fill',
    'cloud': 'icloud.fill',
    'cloud-off': 'icloud.slash.fill',
    'cloud-check': 'checkmark.icloud.fill',
    'upload': 'square.and.arrow.up.fill',
    'download': 'square.and.arrow.down.fill',
    'info': 'info.circle.fill',
    'layout-grid': 'square.grid.2x2.fill',
    'sun-moon': 'circle.lefthalf.filled',
    'languages': 'globe',
    'credit-card': 'creditcard.fill',
    'wallet': 'creditcard.fill',
    'piggy-bank': 'banknote.fill',
    'archive': 'archivebox.fill',
    'equal': 'equal',
    'trash': 'trash.fill',
    'log-out': 'rectangle.portrait.and.arrow.right',
    'chart-pie': 'chart.pie.fill',
    'folder-search': 'folder.fill',
    'shield-check': 'checkmark.shield.fill',
    'circle-user-round': 'person.crop.circle.fill',
    'kind-all': 'doc.text.fill',
    'kind-adjustment': 'equal',
  };

  /// Per-symbol optical nudges (pt), from measuring each tile's glyph bounds against the tile.
  static const Map<String, Offset> _nudge = {
    'download': Offset(0.75, -0.25),
    'sun-moon': Offset(0, 0.25),
    'book-open': Offset(0, 1.0),
    'cloud-off': Offset(0.25, 0),
  };

  static const _fg = Color(0xFFFFFFFF);

  /// The SF Symbol drawn by the system once (macOS 26, regular weight, 80 pt in a 96 pt box) and
  /// kept as a white 192 px mask in assets/sf/ — a plain Flutter image, so the sheet's frosted
  /// bar can blur it. (Live native symbol views are platform views, which split the layer tree and
  /// leave any backdrop blur above them unable to see the content beneath.) Shown in a 22 pt box,
  /// Shown in a 25 pt box, so the symbol fills ~60% of the tile like iOS 26 Settings.
  static Widget _sfImage(String name) => Image.asset('assets/sf/$name.png', width: 25, height: 25, filterQuality: FilterQuality.medium);

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static final Map<String, String> _svgCache = {};
  static String _svg(String name, Color fg, Color bg) => _svgCache.putIfAbsent('$name|${fg.toARGB32()}|${bg.toARGB32()}', () {
        final solid = _glyphs[name];
        if (solid != null) {
          final body = solid.replaceAll('{fg}', _hex(fg)).replaceAll('{bg}', _hex(bg));
          return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">$body</svg>';
        }
        final body = lucideSvgs[name] ?? lucideSvgs['circle-question-mark']!;
        return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
            'stroke="${_hex(fg)}" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
      });

  @override
  Widget build(BuildContext context) {
    final base = color ?? _colors[icon] ?? _gray;
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(7.5));
    // Knock-outs are drawn in the tile's mid colour, so they read as holes through the glyph.
    Widget glyph() => SvgPicture.string(_svg(icon, _fg, Color.lerp(base, Colors.white, 0.06)!), width: 21, height: 21);
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        // iOS 26 Settings: a gentle top-light gradient (a little lighter at the top, the system
        // colour at the bottom), no drop shadow — the tile sits flat on the card.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(base, Colors.white, 0.12)!, base],
        ),
        shape: shape,
      ),
      child: CustomPaint(
        // The rim: 0.75 pt light edge, bright on top, almost gone at the bottom.
        foregroundPainter: _TileRimPainter(shape),
        child: Center(
          child: ExcludeSemantics(
            child: icon == 'check'
                // A bold checkmark like SF's `checkmark` at semibold (the native view only draws
                // regular weight, which is too thin on a 29 pt tile).
                ? const SizedBox.square(dimension: 16, child: CustomPaint(painter: _CheckGlyphPainter()))
                : icon == 'banknote'
                // The currency sign set in SF Pro itself, semibold, as Settings would show `yensign`.
                ? Text('¥', style: cw(18, weight: FontWeight.w600, color: _fg, height: 1.0, spacing: 0))
                : _sfSymbols.containsKey(icon)
                ? Transform.translate(
                    // Optical centring, measured on screen (some symbols' visual centre is off their box).
                    offset: const Offset(0, -0.25) + (_nudge[icon] ?? Offset.zero),
                    child: _sfImage(_sfSymbols[icon]!),
                  )
                : glyph(),
          ),
        ),
      ),
    );
  }
}

class _CheckGlyphPainter extends CustomPainter {
  const _CheckGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.10, h * 0.54)
      ..lineTo(w * 0.38, h * 0.82)
      ..lineTo(w * 0.90, h * 0.18);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CheckGlyphPainter old) => false;
}

class _TileRimPainter extends CustomPainter {
  _TileRimPainter(this.shape);
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.375);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.0)],
        stops: const [0, 0.35, 1],
      ).createShader(rect);
    canvas.drawPath(shape.getOuterPath(rect), paint);
  }

  @override
  bool shouldRepaint(covariant _TileRimPainter old) => old.shape != shape;
}

/// Plain text field styled for a form row.
class FormTextField extends StatelessWidget {
  const FormTextField(
      {super.key,
      required this.controller,
      required this.hint,
      this.keyboardType,
      this.onChanged,
      this.maxLines = 1,
      this.textAlign = TextAlign.start,
      this.focusNode,
      this.inputFormatters,
      this.scrollPadding = const EdgeInsets.all(20)});
  final List<TextInputFormatter>? inputFormatters;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextAlign textAlign;
  final FocusNode? focusNode;
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      scrollPadding: scrollPadding,
      keyboardType: keyboardType,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: 1,
      textAlign: textAlign,
      autocorrect: false,
      inputFormatters: inputFormatters,
      style: cw(IOSText.body, weight: FontWeight.w400, color: p.ink),
      decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
    );
  }
}

/// Menu picker (iOS pull-down style) showing the current value in accent colour with a chevron.
class MenuPicker<T> extends StatelessWidget {
  const MenuPicker({super.key, required this.value, required this.options, required this.label, required this.onChanged, this.placeholder});
  final T? value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option,
            child: Row(children: [
              Expanded(child: Text(label(option), style: cw(IOSText.body, weight: FontWeight.w400, color: p.ink))),
              if (option == value) LIcon('check', size: 16, color: p.accent),
            ]),
          ),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(value == null ? placeholder ?? tr('请选择') : label(value as T),
              style: cw(IOSText.body, weight: FontWeight.w400, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 4),
        LIcon('chevron-up-down', size: 14, color: p.muted),
      ]),
    );
  }
}

/// Money typed into a text field follows the same rules as the 记一笔 keypad: digits and one point,
/// at most 10 whole digits and 2 decimals (and a leading minus when [signed]). Full-width points are
/// accepted. Anything else simply doesn't go in.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({this.signed = false});
  final bool signed;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll('。', '.').replaceAll('．', '.').replaceAll(',', '');
    final pattern = RegExp(signed ? r'^-?\d{0,10}(\.\d{0,2})?$' : r'^\d{0,10}(\.\d{0,2})?$');
    if (!pattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// A form row whose name stays visible next to the value ("期初余额（CNY）  0"), with an inline error
/// line under it. For money and other fields where a placeholder alone isn't enough.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.icon,
    required this.label,
    required this.controller,
    this.hint = '',
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.error,
    this.alignEnd = false,
  });
  final String icon;
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? error;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Same 50 pt height as a FormRow, so a field sits in a group like any Settings row.
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FormRow.minHeight),
        child: Row(children: [
        FormIconTile(icon),
        const SizedBox(width: FormRow.textInset - FormIconTile.size),
        Text(label, style: cw(IOSText.body, color: p.ink)),
        const SizedBox(width: 12),
        Expanded(
          child: FormTextField(
            controller: controller,
            hint: hint,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            textAlign: alignEnd ? TextAlign.right : TextAlign.start,
          ),
        ),
      ]),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: FormRow.textInset, bottom: 10),
          child: Text(error!, style: cw(IOSText.footnote, color: p.over)),
        ),
    ]);
  }
}

/// One choice in [showPullDownMenu].
class PullDownItem<T> {
  const PullDownItem({required this.value, required this.label, this.checked = false});
  final T value;
  final String label;
  final bool checked;
}

/// iOS pull-down menu (UIMenu, as on apple.com's 排序 or any toolbar "…" button): a frosted glass
/// panel that springs out of the button it belongs to, the current choice marked with a ✓ on the
/// left, rows in 17 pt. A tap outside closes it. Returns the picked value, or null.
Future<T?> showPullDownMenu<T>(BuildContext anchor, {required List<PullDownItem<T>> items}) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Navigator.of(anchor).overlay!.context.findRenderObject() as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return Navigator.of(anchor).push(_PullDownRoute<T>(anchorRect: rect, items: items));
}

class _PullDownRoute<T> extends PopupRoute<T> {
  _PullDownRoute({required this.anchorRect, required this.items});
  final Rect anchorRect;
  final List<PullDownItem<T>> items;

  /// The morph: a quick spring with a touch of bounce, like UIKit's menu presentation.
  static final SpringCurve open = SpringCurve(IOSMotion.spring(0.42, 0.18));

  @override
  Color? get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => tr('关闭');
  @override
  Duration get transitionDuration => open.duration;
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return _PullDownMenu<T>(anchorRect: anchorRect, items: items, animation: animation);
  }
}

/// iOS 26 menu presentation: the button itself grows into the menu. The glass shape morphs from the
/// button's bounds (a capsule) to the menu's (large-radius rectangle) on a spring, while the rows
/// come into focus inside it (fade, slight scale, un-blur). Dismissal plays it backwards, faster,
/// shrinking back into the button.
class _PullDownMenu<T> extends StatelessWidget {
  const _PullDownMenu({required this.anchorRect, required this.items, required this.animation});
  final Rect anchorRect;
  final List<PullDownItem<T>> items;
  final Animation<double> animation;

  static const double _width = 250;
  static const double _rowHeight = 48;
  static const double _radius = 26;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final height = items.length * _rowHeight + 16;
    // Right-aligned to the button and just below it, kept on screen; above it when there's no room.
    final left = (anchorRect.right - _width).clamp(12.0, screen.width - _width - 12);
    final below = anchorRect.bottom + 8 + height <= screen.height - padding.bottom - 12;
    final top = below ? anchorRect.bottom + 8 : (anchorRect.top - 8 - height).clamp(padding.top + 8, screen.height);
    final target = Rect.fromLTWH(left, top, _width, height);
    // Start as a capsule around the button (at least 36 pt, so the grow reads as coming from it).
    final start = Rect.fromCenter(
      center: anchorRect.center,
      width: anchorRect.width < 36 ? 36 : anchorRect.width,
      height: anchorRect.height < 36 ? 36 : anchorRect.height,
    );

    final rows = Column(mainAxisSize: MainAxisSize.min, children: [
      for (final item in items)
        Pressable(
          selected: item.checked,
          semanticLabel: item.label,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop(item.value);
          },
          child: SizedBox(
            height: _rowHeight,
            child: Row(children: [
              SizedBox(
                width: 46,
                child: item.checked ? Center(child: LIcon('check', size: 17, color: p.ink, strokeWidth: 2.6)) : null,
              ),
              Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: cw(IOSText.body, color: p.ink))),
              const SizedBox(width: 18),
            ]),
          ),
        ),
    ]);

    return Material(
      // Material gives the text its default style (a bare route would underline it in debug).
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        child: rows,
        builder: (context, rows) {
          final reversing = animation.status == AnimationStatus.reverse;
          final v = animation.value;
          // Shape: spring out (may overshoot slightly), ease back in.
          final m = reversing ? Curves.easeInOutCubic.transform(v) : _PullDownRoute.open.transform(v);
          final rect = Rect.lerp(start, target, m)!;
          final radius = (start.shortestSide / 2) + (_radius - start.shortestSide / 2) * m.clamp(0.0, 1.0);
          // Rows: arrive a beat after the shape starts growing; on close they go first.
          final c = reversing
              ? Curves.easeOut.transform(((v - 0.45) / 0.55).clamp(0.0, 1.0))
              : Curves.easeOut.transform(((v - 0.12) / 0.5).clamp(0.0, 1.0));
          final glass = Curves.easeOut.transform((v / 0.25).clamp(0.0, 1.0));
          return Stack(children: [
            Positioned.fromRect(
              rect: rect,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: (dark ? 0.4 : 0.14) * glass), blurRadius: 40, offset: const Offset(0, 12)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 30 * glass, sigmaY: 30 * glass),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: (dark ? const Color(0xFF2C2C2E) : Colors.white).withValues(alpha: (dark ? 0.78 : 0.72) * glass),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08 * glass), width: 0.5),
                      ),
                      // The rows are laid out at the menu's full size and revealed by the growing shape.
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: _width,
                        maxWidth: _width,
                        minHeight: height,
                        maxHeight: height,
                        child: Transform.translate(
                          offset: Offset(target.left - rect.left, target.top - rect.top),
                          child: Opacity(
                            opacity: c,
                            child: ImageFiltered(
                              imageFilter: ImageFilter.blur(sigmaX: (1 - c) * 6, sigmaY: (1 - c) * 6),
                              child: Transform.scale(
                                scale: 0.92 + 0.08 * c,
                                alignment: Alignment(((anchorRect.center.dx - left) / _width * 2 - 1).clamp(-1.0, 1.0), below ? -1 : 1),
                                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: rows),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

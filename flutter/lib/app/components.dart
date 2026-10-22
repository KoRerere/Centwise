import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/currency.dart';
import '../core/models.dart';
import '../core/money.dart';
import 'icons.dart';
import 'store.dart';
import 'motion.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Tap target without Material ink, dimming slightly while pressed (iOS feel).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.semanticLabel, this.selected = false});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 90),
          opacity: _down ? 0.6 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

/// White rounded card with a hairline border, no shadow.
class CwCard extends StatelessWidget {
  const CwCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 15});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.cardStroke, width: 0.75),
      ),
      child: child,
    );
  }
}

/// Amount with a small raised currency sign — Copilot's signature number style.
class AmountText extends StatelessWidget {
  const AmountText(this.cents, {super.key, this.size = 16, this.weight = FontWeight.w600, this.sign, this.color});
  final int cents;
  final double size;
  final FontWeight weight;

  /// null = automatic ("−" for negative values); "" = never show a sign.
  final String? sign;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final prefix = sign ?? (cents < 0 ? '−' : '');
    final style = cw(size, weight: weight, color: color ?? DefaultTextStyle.of(context).style.color, brand: true);
    return Semantics(
      label: '$prefix${Money.text(cents.abs())}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(
          TextSpan(children: [
            if (prefix.isNotEmpty) TextSpan(text: prefix),
            // Smaller ¥ sitting on the same baseline as the digits.
            TextSpan(text: Money.symbol, style: style.copyWith(fontSize: size * 0.6, letterSpacing: size * 0.04)),
            TextSpan(text: Money.text(cents.abs(), symbol: false)),
          ]),
          style: style,
          maxLines: 1,
        ),
      ),
    );
  }
}

/// A translated sentence with one money amount in it, e.g. tr('比昨天同期多花 {amount}'): the words use
/// [style], the amount the brand number style. Works for any word order the translation uses.
class TextWithAmount extends StatelessWidget {
  const TextWithAmount(this.template, this.cents, {super.key, required this.style, this.amountColor});
  final String template;
  final int cents;
  final TextStyle style;

  /// Colour for the amount only (e.g. green / red for less / more); the words keep [style].
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    final parts = template.split('{amount}');
    final number = cw(style.fontSize ?? 14, weight: FontWeight.w600, color: amountColor ?? style.color, brand: true);
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans
          ..add(TextSpan(text: Money.symbol, style: number.copyWith(fontSize: (style.fontSize ?? 14) * 0.8)))
          ..add(TextSpan(text: Money.text(cents.abs(), symbol: false), style: number));
      }
      if (parts[i].isNotEmpty) spans.add(TextSpan(text: parts[i]));
    }
    return Text.rich(TextSpan(children: spans), style: style, maxLines: 1);
  }
}

/// Small spaced caption used above every card, e.g. "待核对" / "近六个月".
class CardCaption extends StatelessWidget {
  const CardCaption(this.title, {super.key, this.trailing, this.onTap});
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: cw(15, weight: FontWeight.w600, color: p.ink)),
        const Spacer(),
        if (trailing != null)
          onTap == null
              ? Text(trailing!, style: cw(13, weight: FontWeight.w400, color: p.muted))
              : Pressable(
                  onTap: onTap,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(trailing!, style: cw(13, weight: FontWeight.w600, color: p.accent)),
                    LIcon('chevron-right', size: 14, color: p.accent, strokeWidth: 2.5),
                  ]),
                ),
      ],
    );
  }
}

/// Tinted capsule label for a category.
class CategoryPill extends StatelessWidget {
  const CategoryPill({super.key, required this.name, required this.icon, required this.tint});
  final String name;
  final String icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        LIcon(icon, size: 11, color: tint, strokeWidth: 2.5),
        const SizedBox(width: 4),
        Text(name, style: cw(11, weight: FontWeight.w700, color: tint), maxLines: 1),
      ]),
    );
  }
}

/// Rounded budget bar with a coloured fill and a light track.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.ratio, this.height = 7, this.color});
  final double ratio;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final double clamped = ratio.isNaN ? 0.0 : ratio.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      // Always the full available width: the track is the 100% mark, the fill grows from the left.
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: p.track)),
          // Fill grows from the left edge over the full light track.
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: clamped,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color ?? p.budgetColor(ratio), borderRadius: BorderRadius.circular(height)),
              child: SizedBox(height: height),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "已用 60% · 正常" under a budget bar, so the state never depends on colour alone.
class BudgetUsageLine extends StatelessWidget {
  const BudgetUsageLine({super.key, required this.ratio});
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final percent = ratio.isNaN || ratio.isInfinite ? 0 : (ratio * 100).round();
    final (status, color) = ratio >= 1
        ? (tr('已超出预算'), p.over)
        : ratio >= 0.8
            ? (tr('接近上限'), p.warning)
            : (tr('正常'), p.under);
    return Row(children: [
      Text(tr('已用 {percent}%', {'percent': percent}), style: cw(12, color: p.muted)),
      const Spacer(),
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(status, style: cw(12, weight: FontWeight.w500, color: p.ink)),
    ]);
  }
}

/// Floating period selector: ‹ [今天 | 本月 | 近一年] ›.
/// Height of the floating period capsule / 记一笔 row (without the home-indicator inset).
const double bottomControlsHeight = 68;

/// Bottom padding a page list needs so its last row can scroll clear of the floating bottom controls.
double bottomControlsClearance(BuildContext context, {double extra = 24}) =>
    bottomControlsHeight + MediaQuery.paddingOf(context).bottom + extra;

/// A row of items with one pill-shaped highlight behind them that slides between items, like an iOS
/// segmented control. [position] is a (possibly fractional) item index: drive it with a spring or a
/// PageController and the pill glides and stretches between neighbours instead of blinking.
/// [itemBuilder] gets each item's "selectedness" (1 = under the pill, 0 = one item away or more), so
/// labels can crossfade their colour in step with the pill.
class PillTrack extends StatefulWidget {
  const PillTrack({
    super.key,
    required this.count,
    required this.listenable,
    required this.position,
    required this.itemBuilder,
    required this.pill,
    this.spacing = 0,
  });
  final int count;
  final Listenable listenable;
  final double Function() position;
  final Widget Function(BuildContext context, int index, double selectedness) itemBuilder;
  final BoxDecoration pill;
  final double spacing;

  @override
  State<PillTrack> createState() => _PillTrackState();
}

class _PillTrackState extends State<PillTrack> {
  final GlobalKey _stack = GlobalKey();
  late List<GlobalKey> _keys = [for (var i = 0; i < widget.count; i++) GlobalKey()];
  List<Rect> _rects = const [];

  @override
  void didUpdateWidget(covariant PillTrack old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _keys = [for (var i = 0; i < widget.count; i++) GlobalKey()];
  }

  // Item rects are measured after layout; labels can change width (e.g. 今天 → 10月18日), so re-measure
  // every frame something rebuilds and only setState when they actually moved.
  void _measure() {
    if (!mounted) return;
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return;
    final rects = <Rect>[];
    for (final key in _keys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      rects.add(box.localToGlobal(Offset.zero, ancestor: stack) & box.size);
    }
    var same = rects.length == _rects.length;
    for (var i = 0; same && i < rects.length; i++) {
      same = (rects[i].left - _rects[i].left).abs() < 0.5 && (rects[i].width - _rects[i].width).abs() < 0.5;
    }
    if (!same) setState(() => _rects = rects);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return AnimatedBuilder(
      animation: widget.listenable,
      builder: (context, _) {
        final position = widget.position().clamp(0.0, (widget.count - 1).toDouble());
        Rect? pill;
        if (_rects.length == widget.count) {
          final i = position.floor().clamp(0, widget.count - 1);
          final j = (i + 1).clamp(0, widget.count - 1);
          pill = Rect.lerp(_rects[i], _rects[j], position - i);
        }
        return Stack(key: _stack, children: [
          if (pill != null) Positioned.fromRect(rect: pill, child: DecoratedBox(decoration: widget.pill)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < widget.count; i++) ...[
              if (i > 0 && widget.spacing > 0) SizedBox(width: widget.spacing),
              KeyedSubtree(
                key: _keys[i],
                child: widget.itemBuilder(context, i, (1 - (position - i).abs()).clamp(0.0, 1.0)),
              ),
            ],
          ]),
        ]);
      },
    );
  }
}

/// 今天 / 本月 / 近一年 with step arrows, on frosted glass. The selection pill slides between segments on
/// a snappy spring.
class PeriodCapsule extends StatefulWidget {
  const PeriodCapsule({super.key});

  @override
  State<PeriodCapsule> createState() => _PeriodCapsuleState();
}

class _PeriodCapsuleState extends State<PeriodCapsule> with SingleTickerProviderStateMixin {
  static const _periods = [Period.day, Period.month, Period.year];
  late final AnimationController _pos = AnimationController.unbounded(vsync: this);
  bool _placed = false;
  double _target = 0;

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final target = _periods.indexOf(store.period).toDouble();
    if (!_placed) {
      _pos.value = target;
      _target = target;
      _placed = true;
    } else if (target != _target) {
      // Retarget (also mid-flight), carrying the current velocity like UIKit.
      _target = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) IOSMotion.animate(_pos, target, spring: IOSMotion.snappy, velocity: _pos.velocity);
      });
    }
    String stepLabel(int v) => switch (store.period) {
          Period.day => v < 0 ? tr('前一天') : tr('后一天'),
          Period.month => v < 0 ? tr('上个月') : tr('下个月'),
          Period.year => v < 0 ? tr('前一年') : tr('后一年'),
        };
    Widget arrow(int value) => Pressable(
          semanticLabel: stepLabel(value),
          onTap: () => store.stepPeriod(value),
          child: SizedBox(
            width: 30,
            height: 36,
            child: Center(child: LIcon(value < 0 ? 'chevron-left' : 'chevron-right', size: 16, color: p.ink, strokeWidth: 2.5)),
          ),
        );
    final fallbacks = [tr('今天'), tr('本月'), tr('近一年')];

    // Frosted glass: blur what scrolls underneath and let a little of it show through.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.card.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: p.cardStroke.withValues(alpha: 0.7), width: 0.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              arrow(-1),
              PillTrack(
                count: _periods.length,
                listenable: _pos,
                position: () => _pos.value,
                pill: BoxDecoration(color: p.brand, borderRadius: BorderRadius.circular(99)),
                itemBuilder: (context, i, t) {
                  final period = _periods[i];
                  final selected = store.period == period;
                  return Pressable(
                    selected: selected,
                    onTap: () => store.select(period),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 50),
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      alignment: Alignment.center,
                      child: Text(selected ? store.periodName : fallbacks[i],
                          style: cw(14, weight: FontWeight.w600, color: Color.lerp(p.muted, p.onBrand, t)), maxLines: 1),
                    ),
                  );
                },
              ),
              arrow(1),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Plays a short settle-in (fade up from 35 % and 8 pt lower, smooth spring) whenever [trigger] changes —
/// used for page content when the period changes, so new figures arrive instead of snapping in.
class ContentTransition extends StatefulWidget {
  const ContentTransition({super.key, required this.trigger, required this.child});
  final Object trigger;
  final Widget child;

  @override
  State<ContentTransition> createState() => _ContentTransitionState();
}

class _ContentTransitionState extends State<ContentTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(covariant ContentTransition old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _t.value = 0;
      IOSMotion.animate(_t, 1, spring: IOSMotion.smooth);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) {
          final v = _t.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: 0.35 + 0.65 * v,
            child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
          );
        },
      );
}

/// "已删除账单 · 撤销", shown for a few seconds after a bill is deleted (swipe, long-press or the editor).
class UndoDeleteToast extends StatelessWidget {
  const UndoDeleteToast({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final count = store.recentlyDeleted.length;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xFF2C2C2E) : const Color(0xFF0A0A0A);
    final child = count == 0
        ? const SizedBox.shrink(key: ValueKey('none'))
        : Container(
            key: const ValueKey('toast'),
            constraints: const BoxConstraints(maxWidth: 360),
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const LIcon('trash', size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Flexible(
                child: Semantics(
                  liveRegion: true,
                  child: Text(count == 1 ? tr('已删除账单') : tr('已删除 {n} 笔账单', {'n': count}),
                      style: cw(14, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 10),
              Pressable(
                semanticLabel: tr('撤销删除'),
                onTap: () {
                  HapticFeedback.selectionClick();
                  store.undoDelete();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const LIcon('undo-2', size: 15, color: Colors.white, strokeWidth: 2.5),
                    const SizedBox(width: 4),
                    Text(tr('撤销'), style: cw(14, weight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          );
    return AnimatedSwitcher(
      duration: IOSMotion.bouncyCurve.duration,
      reverseDuration: IOSMotion.smoothCurve.duration,
      switchInCurve: IOSMotion.bouncyCurve,
      switchOutCurve: IOSMotion.smoothCurve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Round floating action button (Copilot's "+").
class FloatingCircleButton extends StatelessWidget {
  const FloatingCircleButton({super.key, required this.icon, required this.label, this.onTap});
  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      semanticLabel: label,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: p.brand,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Center(child: LIcon(icon, size: 24, color: p.onBrand, strokeWidth: 2.5)),
      ),
    );
  }
}

/// Full-width black capsule action button (Trackly-style: label centred, optional icon).
class PrimaryBarButton extends StatelessWidget {
  const PrimaryBarButton({super.key, required this.label, this.onTap, this.tint, this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color? tint;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: IOSMotion.snappyCurve.duration,
        curve: IOSMotion.snappyCurve,
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: enabled ? (tint ?? p.brand) : p.muted.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[LIcon(icon!, size: 18, color: p.onBrand, strokeWidth: 2.5), const SizedBox(width: 6)],
          Text(label, style: cw(17, weight: FontWeight.w600, color: p.onBrand.withValues(alpha: enabled ? 1 : 0.85))),
        ]),
      ),
    );
  }
}

/// Capsule segmented control (type switch, refund switch).
class CapsuleSegments<T> extends StatelessWidget {
  const CapsuleSegments({super.key, required this.values, required this.selected, required this.label, required this.onChanged, this.expand = true, this.height = 34});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget item(T value) {
      final on = value == selected;
      final child = Pressable(
        selected: on,
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: IOSMotion.snappyCurve.duration,
          curve: IOSMotion.snappyCurve,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: expand ? 0 : 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? p.card : Colors.transparent, borderRadius: BorderRadius.circular(99)),
          child: Text(label(value), style: cw(14, weight: on ? FontWeight.w700 : FontWeight.w400, color: on ? p.ink : p.muted)),
        ),
      );
      return expand ? Expanded(child: child) : child;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: p.track.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, children: [
        for (var i = 0; i < values.length; i++) ...[if (i > 0) const SizedBox(width: 4), item(values[i])]
      ]),
    );
  }
}

/// Copilot transaction row: name · category pill · amount. Swipe left (or long-press) to delete.
class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry, this.showDate = false, this.onTap});
  final Entry entry;
  final bool showDate;
  final VoidCallback? onTap;

  Future<void> _showActions(BuildContext context, String title) async {
    HapticFeedback.mediumImpact();
    final store = StoreScope.read(context);
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          CupertinoActionSheetAction(
              isDestructiveAction: true, onPressed: () => Navigator.of(sheet).pop('delete'), child: Text(tr('删除记录'))),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.of(sheet).pop(), child: Text(tr('取消'))),
      ),
    );
    if (action == 'delete') store.deleteEntry(entry);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final p = Palette.of(context);
    final category = entry.allocations.length == 1 ? store.category(entry.allocations.first.categoryID) : null;
    // Title: what kind of bill it is — the category (a subcategory as "住宅 › 租金"), or 转账 / 余额调整 /
    // 分摊. Second line: the note (or payee) when there is one; no account name for ordinary bills.
    String categoryLabel(LedgerCategory c) {
      final parent = c.parentID == null ? null : store.ledger.categoryByID(c.parentID!);
      return parent == null ? c.name : '${parent.name} › ${c.name}';
    }

    final String title = switch (entry.kind) {
      EntryKind.transfer => tr('转账'),
      EntryKind.adjustment => tr('余额调整'),
      _ => category != null
          ? categoryLabel(category)
          : entry.allocations.length > 1
              ? tr('{n} 项分摊', {'n': entry.allocations.length})
              : store.categoryName(entry),
    };
    final memo = entry.note.isNotEmpty ? entry.note : entry.payee;
    final sign = switch (entry.kind) {
      EntryKind.expense => entry.amount < 0 ? '+' : '',
      EntryKind.income => entry.amount < 0 ? '−' : '+',
      EntryKind.transfer => '',
      EntryKind.adjustment => entry.amount < 0 ? '−' : '+',
    };
    final Color amountColor;
    if ((entry.kind == EntryKind.income && entry.amount > 0) || (entry.kind == EntryKind.expense && entry.amount < 0)) {
      amountColor = p.income;
    } else {
      amountColor = entry.kind == EntryKind.adjustment ? p.muted : p.ink;
    }
    // Left: the category icon (its colour lives here only). Middle: note / payee, or the category when
    // there is neither, with a small second line for whatever isn't already said. Right: the amount.
    final (String, Color) look = switch (entry.kind) {
      EntryKind.transfer => ('arrow-left-right', p.muted),
      EntryKind.adjustment => ('equal', p.muted),
      _ => category != null ? (categoryIcon(category), categoryTint(category.id)) : ('split', p.muted),
    };
    final (icon, tint) = look;
    final details = <String>[
      if (entry.kind == EntryKind.transfer)
        '${store.accountName(entry.accountID)} → ${entry.destinationID == null ? '—' : store.accountName(entry.destinationID!)}'
      else if (entry.kind == EntryKind.adjustment)
        store.accountName(entry.accountID),
      if (memo.isNotEmpty) memo,
      if (showDate) fmtMonthDay(entry.date),
      if (entry.pending) tr('待入账'),
      if (entry.needsReview) tr('待核对'),
    ];
    final row = Pressable(
      onTap: onTap,
      onLongPress: () => _showActions(context, title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          // Category bills show the 3D emoji on its own (no tinted disc); transfers and the like keep
          // their line icon on a disc.
          if (category != null && (entry.kind == EntryKind.expense || entry.kind == EntryKind.income))
            SizedBox(width: 36, height: 36, child: Center(child: CategoryIcon(category, size: 26, color: tint)))
          else
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Center(child: LIcon(icon, size: 17, color: tint)),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: cw(16, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(details.join(' · '),
                    style: cw(12, color: entry.needsReview ? p.over : p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          AmountText(entry.amount, size: 16, weight: FontWeight.w600, sign: sign, color: amountColor),
        ]),
      ),
    );
    return SwipeToDelete(key: ValueKey(entry.id), onDelete: () => StoreScope.read(context).deleteEntry(entry), child: row);
  }
}

/// iOS-style swipe action: drag the row left to reveal a red 删除 button (tap it, or keep swiping all
/// the way, to delete). Only one row is open at a time. Rows take every horizontal drag, so swiping
/// over the bill list never switches tabs; that only happens outside the list.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({super.key, required this.child, required this.onDelete});
  final Widget child;
  final VoidCallback onDelete;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> with SingleTickerProviderStateMixin {
  // Revealed area when open: a 12 pt gap after the amount, then the 76 pt red button.
  static const double _gap = 12;
  static const double _buttonWidth = 76;
  static const double _actionWidth = _gap + _buttonWidth;
  // Past the open position the row follows the finger with iOS-style rubber-band resistance and can
  // only stretch this much further, so a long swipe never deletes on its own.
  static const double _maxStretch = 36;

  double _drag = 0; // finger position, before rubber-banding

  static double _rubberBand(double drag) {
    final pull = -drag;
    if (pull <= _actionWidth) return drag;
    final extra = pull - _actionWidth;
    return -(_actionWidth + (1 - 1 / (extra * 0.55 / _maxStretch + 1)) * _maxStretch);
  }
  static final ValueNotifier<_SwipeToDeleteState?> _openRow = ValueNotifier(null);

  late final AnimationController _offset =
      AnimationController(vsync: this, lowerBound: -10000, upperBound: 0, value: 0);

  bool get _isOpen => _offset.value < -1;

  @override
  void initState() {
    super.initState();
    _openRow.addListener(_onAnotherRowOpened);
  }

  @override
  void dispose() {
    _openRow.removeListener(_onAnotherRowOpened);
    if (_openRow.value == this) _openRow.value = null;
    _offset.dispose();
    super.dispose();
  }

  void _onAnotherRowOpened() {
    if (_openRow.value != this && _isOpen) IOSMotion.animate(_offset, 0, spring: IOSMotion.snappy);
  }

  // Swipe actions follow UIKit: a snappy spring that picks up the finger's release velocity.
  void _close([double velocity = 0]) {
    IOSMotion.animate(_offset, 0, spring: IOSMotion.snappy, velocity: velocity);
    if (_openRow.value == this) _openRow.value = null;
  }

  void _open([double velocity = 0]) {
    IOSMotion.animate(_offset, -_actionWidth, spring: IOSMotion.snappy, velocity: velocity);
    _openRow.value = this;
  }

  Future<void> _delete(double width, [double velocity = 0]) async {
    HapticFeedback.mediumImpact();
    await IOSMotion.animate(_offset, -width, spring: IOSMotion.smooth, velocity: velocity);
    widget.onDelete();
    if (mounted) _offset.value = 0;
    if (_openRow.value == this) _openRow.value = null;
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return RawGestureDetector(
        gestures: {
          _LeftSwipeRecognizer: GestureRecognizerFactoryWithHandlers<_LeftSwipeRecognizer>(
            () => _LeftSwipeRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..allowRightward = (() => true)
              ..onStart = (_) {
                _offset.stop();
                _drag = _offset.value;
              }
              ..onUpdate = (details) {
                _drag = math.max(-width, math.min(0, _drag + (details.primaryDelta ?? 0)));
                _offset.value = _rubberBand(_drag);
              }
              ..onEnd = (details) {
                // No full-swipe delete: releasing anywhere past half the button opens it; delete is a tap.
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -300 || (velocity <= 300 && _offset.value < -_actionWidth / 2)) {
                  _open(velocity);
                } else {
                  _close(velocity);
                }
              },
          ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _offset,
            child: widget.child,
            builder: (context, child) {
              final reveal = -_offset.value;
              return Stack(children: [
                if (reveal > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => _delete(width),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: reveal,
                          padding: EdgeInsets.only(left: math.min(_gap, reveal), top: 4, bottom: 4),
                          child: Container(
                          decoration: BoxDecoration(color: p.over, borderRadius: BorderRadius.circular(12)),
                          alignment: Alignment.center,
                          child: reveal > 60
                              ? Column(mainAxisSize: MainAxisSize.min, children: [
                                  const LIcon('trash', size: 18, color: Colors.white),
                                  const SizedBox(height: 2),
                                  Text(tr('删除'), style: cw(12, weight: FontWeight.w600, color: Colors.white)),
                                ])
                              : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(offset: Offset(_offset.value, 0), child: child),
                // While open, a tap on the row closes it instead of opening the entry.
                if (reveal > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    right: reveal,
                    child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close),
                  ),
              ]);
            },
          ),
        ),
      );
    });
  }
}

/// Horizontal drag for a row. With [allowRightward] false it would only claim leftward drags and leave
/// rightward ones to the PageView; the bill list currently claims both directions.
class _LeftSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _LeftSwipeRecognizer({super.debugOwner});

  bool Function() allowRightward = () => false;
  double _dx = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _dx = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _dx += event.delta.dx;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    final slop = computeHitSlop(pointerDeviceKind, gestureSettings);
    return allowRightward() ? _dx.abs() > slop : _dx < -slop;
  }
}

/// Thin, light line between bill rows, starting under the text (past the icon).
class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = 48});
  final double indent;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: indent), child: Divider(height: 1, thickness: 0.5, color: Palette.of(context).cardStroke));
}

/// Faint dashed line between bill rows.
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(Palette.of(context).cardStroke)),
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + dash, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

/// Small grey day heading used in transaction lists ("10月13日 星期二" / "今天").
class DayHeading extends StatelessWidget {
  const DayHeading(this.day, {super.key, this.centered = false});
  final DateTime day;
  final bool centered;

  static String label(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(DateTime(day.year, day.month, day.day)).inDays;
    if (difference == 0) return tr('今天');
    if (difference == 1) return tr('昨天');
    return fmtDayHeading(day);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      width: double.infinity,
      child: Text(label(day),
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: cw(13, weight: FontWeight.w500, color: p.muted)),
    );
  }
}

/// Groups entries (already sorted newest first) by calendar day.
List<(DateTime, List<Entry>)> groupedByDay(Iterable<Entry> entries) {
  final result = <(DateTime, List<Entry>)>[];
  for (final entry in entries) {
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    if (result.isNotEmpty && result.last.$1 == day) {
      result.last.$2.add(entry);
    } else {
      result.add((day, [entry]));
    }
  }
  return result;
}

/// Light haptic tick, used by the number pad.
void tick() => HapticFeedback.selectionClick();

/// Round country / region flag from assets/flags (bundled SVGs, not emoji).
class FlagIcon extends StatelessWidget {
  const FlagIcon(this.code, {super.key, this.size = 20});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: SvgPicture.asset('assets/flags/$code.svg', width: size, height: size));
}

/// "🇨🇳 人民币 CNY" with a real flag: the ledger currency as shown in settings rows.
class CurrencyLabel extends StatelessWidget {
  const CurrencyLabel(this.code, {super.key, this.color});
  final String code;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final currency = currencyFor(code);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      FlagIcon(currency.flag, size: 18),
      const SizedBox(width: 6),
      Text('${currency.name} ${currency.code}', style: cw(15, color: color ?? Palette.of(context).muted)),
    ]);
  }
}

/// Empty state: a simple blue-gradient illustration (or a 3D emoji on a soft disc), a line of text, an
/// optional hint and action.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, this.illustration, this.message, this.actionLabel, this.onAction});

  /// Illustration in assets/illustrations (e.g. 'receipt'; the `-dark.svg` variant is used in dark mode);
  /// shown instead of [icon] when set.
  final String? illustration;

  /// Category-icon key for the 3D picture (see [categoryEmoji3D]), e.g. 'receipt'.
  final String icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (illustration != null)
          ExcludeSemantics(
            child: SvgPicture.asset(
              'assets/illustrations/$illustration${Theme.of(context).brightness == Brightness.dark ? '-dark' : ''}.svg',
              height: 96,
            ),
          )
        else
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.08), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Emoji3DIcon(icon, size: 40),
          ),
        SizedBox(height: illustration != null ? 16 : 12),
        Text(title, textAlign: TextAlign.center, style: cw(15, weight: FontWeight.w500, color: p.ink)),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(message!, textAlign: TextAlign.center, style: cw(13, color: p.muted, height: 1.4)),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          Pressable(
            onTap: onAction,
            semanticLabel: actionLabel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                LIcon('plus', size: 15, color: p.accent, strokeWidth: 2.5),
                const SizedBox(width: 4),
                Text(actionLabel!, style: cw(14, weight: FontWeight.w600, color: p.accent)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

import 'dart:io' show Platform;
import 'dart:math' as math;

import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart' show CNSegmentedControl, CNSwitch;
import 'package:flutter_svg/flutter_svg.dart';

import '../core/currency.dart';
import '../core/models.dart';
import '../core/money.dart';
import 'icons.dart';
import 'store.dart';
import 'motion.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Top inset the tab pages must reserve for the floating frosted header (status pad + demo banner +
/// title row + tabs): their content starts below it and scrolls up behind the header's frost.
class HeaderInset extends InheritedWidget {
  const HeaderInset({super.key, required this.height, required super.child});
  final double height;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HeaderInset>()?.height ?? 0;

  @override
  bool updateShouldNotify(HeaderInset old) => old.height != height;
}

/// Tap target without Material ink, dimming slightly while pressed (iOS feel). With [pressScale] below 1
/// it also shrinks under the finger (a quick, bounce-free spring) and springs back with a small
/// overshoot on release — for prominent buttons like the "+" and the save bar.
class Pressable extends StatefulWidget {
  const Pressable(
      {super.key, required this.child, this.onTap, this.onLongPress, this.semanticLabel, this.selected = false, this.pressScale = 1});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool selected;
  final double pressScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> with SingleTickerProviderStateMixin {
  bool _down = false;
  AnimationController? _scaleController;
  AnimationController get _scale => _scaleController ??= AnimationController.unbounded(vsync: this, value: 1);

  // Finger down: fast and flat. Finger up: a livelier spring that overshoots 1 a touch.
  static final SpringDescription _pressIn = IOSMotion.spring(0.22, 0);
  static final SpringDescription _pressOut = IOSMotion.spring(0.45, 0.4);

  void _setDown(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
    if (widget.pressScale == 1 || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) return;
    IOSMotion.animate(_scale, down ? widget.pressScale : 1,
        spring: down ? _pressIn : _pressOut, velocity: _scale.velocity);
  }

  @override
  void dispose() {
    _scaleController?.dispose();
    super.dispose();
  }

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
        onTapDown: enabled ? (_) => _setDown(true) : null,
        onTapCancel: enabled ? () => _setDown(false) : null,
        onTapUp: enabled ? (_) => _setDown(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 90),
          // 0.45 rather than the usual dim: white keys and cards must read as clearly darker; scaling
          // buttons dim less, since the shrink already shows the press.
          opacity: _down ? (widget.pressScale == 1 ? 0.45 : 0.8) : 1,
          child: widget.pressScale == 1
              ? widget.child
              : AnimatedBuilder(
                  animation: _scale,
                  child: widget.child,
                  builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
                ),
        ),
      ),
    );
  }
}

/// iOS inset-grouped card: plain white (#1C1C1E in dark mode) on the grey canvas, no border, no shadow.
class CwCard extends StatelessWidget {
  const CwCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 14});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        // iOS grouped-card shadow: barely there, just enough to lift the card off the canvas.
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.22 : 0.022), blurRadius: 8, offset: const Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

/// Amount with a small raised currency sign — Copilot's signature number style.
class AmountText extends StatelessWidget {
  const AmountText(this.cents, {super.key, this.size = 16, this.weight = FontWeight.w600, this.sign, this.color, this.brand = true});
  final int cents;

  /// false: the system font (SF) instead of the rounded brand numerals — for amounts in lists.
  final bool brand;
  final double size;
  final FontWeight weight;

  /// null = automatic ("−" for negative values); "" = never show a sign.
  final String? sign;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final prefix = sign ?? (cents < 0 ? '−' : '');
    final style = cw(size, weight: weight, color: color ?? DefaultTextStyle.of(context).style.color, brand: brand);
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

/// Section title above a card, iOS style (Health / Fitness): bold Title 3 on the left, a grey
/// "共 n 笔 ›" link or note on the right.
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
        // The title takes the free width (so a long one ellipsizes) and the link sits flush right.
        Expanded(child: Text(title, style: cw(IOSText.title3, weight: FontWeight.w700, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        if (trailing != null)
          onTap == null
              ? Text(trailing!, style: cw(IOSText.subheadline, color: p.muted))
              : Pressable(
                  onTap: onTap,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(trailing!, style: cw(IOSText.subheadline, color: p.muted)),
                    const SizedBox(width: 2),
                    LIcon('chevron-right', size: 14, color: p.muted.withValues(alpha: 0.8)),
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
      Text(tr('已用 {percent}%', {'percent': percent}), style: cw(IOSText.footnote, color: p.muted)),
      const Spacer(),
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(status, style: cw(IOSText.footnote, color: p.ink)),
    ]);
  }
}

/// Floating period selector: ‹ [今天 | 本月 | 近一年] ›.
/// Height of the floating period capsule / 记一笔 row (without the home-indicator inset).
const double bottomControlsHeight = 68;

/// Bottom padding a page list needs so its last row can scroll clear of the floating bottom controls.
double bottomControlsClearance(BuildContext context, {double extra = 24}) =>
    bottomControlsHeight + MediaQuery.paddingOf(context).bottom + extra;

/// Gives [child] a small spring "pop" (dips to 86 %, overshoots a little, settles) each time [selected]
/// turns on — e.g. a category the user just picked. Skipped when Reduce Motion is on.
class SelectPop extends StatefulWidget {
  const SelectPop({super.key, required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  State<SelectPop> createState() => _SelectPopState();
}

class _SelectPopState extends State<SelectPop> with SingleTickerProviderStateMixin {
  late final AnimationController _scale = AnimationController.unbounded(vsync: this, value: 1);
  static final SpringDescription _pop = IOSMotion.spring(0.42, 0.45);

  @override
  void didUpdateWidget(covariant SelectPop old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _scale.value = 0.86;
      IOSMotion.animate(_scale, 1, spring: _pop);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _scale,
        child: widget.child,
        builder: (context, child) => Transform.scale(scale: _scale.value, child: child),
      );
}

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

    // Frosted tinted capsule: a 10 % ink wash (10 % white in dark mode) over a backdrop blur, so the
    // capsule reads as its own layer against the white cards scrolling behind it.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              arrow(-1),
              PillTrack(
                count: _periods.length,
                listenable: _pos,
                position: () => _pos.value,
                // Tinted glass: the black thumb carries a faint sheen across its top half.
                pill: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color.lerp(p.brand, Colors.white, 0.16)!, p.brand, p.brand],
                    stops: const [0, 0.5, 1],
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                itemBuilder: (context, i, t) {
                  final period = _periods[i];
                  final selected = store.period == period;
                  return Pressable(
                    selected: selected,
                    onTap: () {
                      if (!selected) HapticFeedback.selectionClick();
                      store.select(period);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 50),
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      alignment: Alignment.center,
                      // Stepping (今天 → 10月26日 …) crossfades the label. The capsule takes the new label's
                      // width at once (so the pill measures it), the old one fades out over it.
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (current, previous) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                          for (final old in previous)
                            Positioned.fill(child: OverflowBox(maxWidth: double.infinity, child: Center(child: old))),
                          if (current != null) current,
                        ]),
                        child: Text(selected ? store.periodName : fallbacks[i],
                            key: ValueKey(selected ? store.periodName : fallbacks[i]),
                            style: cw(14, weight: FontWeight.w600, color: Color.lerp(p.muted, p.onBrand, t)), maxLines: 1),
                      ),
                    ),
                  );
                },
              ),
              arrow(1),
            ]),
          ),
        ),
      );
  }
}

/// Flat card-white surface for floating controls (search bar, period capsule): pure white in light
/// mode, the dark card colour in dark mode. No translucency, no shadow — the pills read like cards.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.padding = EdgeInsets.zero, this.radius = 99, this.circle = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// A round button: drawn exactly circular.
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = circle ? const CircleBorder() : RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));
    return DecoratedBox(
      decoration: ShapeDecoration(color: dark ? const Color(0xFF1C1C1E) : Colors.white, shape: shape),
      child: Padding(padding: padding, child: child),
    );
  }
}


/// iOS switch. On iPhone this is Apple's own UISwitch (hosted through cupertino_native_better), so it
/// looks and animates exactly like the system's on whatever iOS the phone runs (iOS 26 / 27 Liquid
/// Glass). Elsewhere — the Mac preview — it is a hand-made UISwitch replica, see [_ReplicaSwitch].
class IOSSwitch extends StatelessWidget {
  const IOSSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      final native = SizedBox(
        width: 63,
        height: 28,
        child: CNSwitch(value: value, onChanged: onChanged ?? (_) {}),
      );
      return onChanged == null ? IgnorePointer(child: Opacity(opacity: 0.45, child: native)) : native;
    }
    return _ReplicaSwitch(value: value, onChanged: onChanged);
  }
}

/// Hand-made UISwitch replica for platforms without UIKit (the Mac preview): the system's 51 × 31 pt
/// track with its green / grey states, a plain white round thumb (27 pt) carrying UIKit's contact
/// shadow, and the same bouncy spring slide. Tap or drag; one light tick when the value changes.
class _ReplicaSwitch extends StatefulWidget {
  const _ReplicaSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<_ReplicaSwitch> createState() => _ReplicaSwitchState();
}

class _ReplicaSwitchState extends State<_ReplicaSwitch> with SingleTickerProviderStateMixin {
  // UISwitch's own metrics: 51 × 31 track, 27 pt round thumb, 2 pt inset.
  static const double _width = 51, _height = 31, _inset = 2, _thumb = 27;

  /// Thumb position, 0 = off … 1 = on (spring-driven, overshoots a little like UIKit's).
  late final AnimationController _t = AnimationController.unbounded(vsync: this, value: widget.value ? 1 : 0);

  bool _down = false;

  double get _travel => _width - 2 * _inset - _thumb;

  @override
  void didUpdateWidget(covariant _ReplicaSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_down) _moveTo(widget.value);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _press() {
    _down = true;
    _t.stop();
  }

  void _moveTo(bool on, [double velocity = 0]) {
    IOSMotion.animate(_t, on ? 1 : 0, spring: IOSMotion.bouncy, velocity: velocity);
  }

  void _release(bool on, [double velocity = 0]) {
    _down = false;
    _moveTo(on, velocity);
    if (on != widget.value) {
      HapticFeedback.lightImpact();
      widget.onChanged?.call(on);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final enabled = widget.onChanged != null;
    final onColor = dark ? const Color(0xFF30D158) : const Color(0xFF34C759);
    final offColor = dark ? const Color(0xFF39393D) : const Color(0xFFE9E9EB);
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press() : null,
        onTapCancel: enabled
            ? () {
                _down = false;
                _moveTo(widget.value);
              }
            : null,
        onTap: enabled ? () => _release(!widget.value) : null,
        onHorizontalDragStart: enabled ? (_) => _press() : null,
        onHorizontalDragUpdate: enabled ? (d) => _t.value = (_t.value + d.delta.dx / _travel).clamp(0.0, 1.0) : null,
        onHorizontalDragEnd: enabled
            ? (d) {
                final v = (d.primaryVelocity ?? 0) / _travel;
                _release(v.abs() > 3 ? v > 0 : _t.value > 0.5, v);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) {
              final t = _t.value;
              final cx = _inset + _thumb / 2 + t * _travel;
              return SizedBox(
                width: _width,
                height: _height,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(offColor, onColor, Curves.easeOut.transform(t.clamp(0.0, 1.0)))!,
                        borderRadius: BorderRadius.circular(_height / 2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: cx - _thumb / 2,
                    top: _inset,
                    width: _thumb,
                    height: _thumb,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        // UIKit's thumb shadow: a soft drop plus a tight contact edge.
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 4.5, offset: const Offset(0, 2.5)),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 1, offset: const Offset(0, 0.5)),
                        ],
                      ),
                    ),
                  ),
                ]),
              );
            },
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
      pressScale: 0.88,
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
      pressScale: 0.97,
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
          Text(label, style: cw(17, weight: FontWeight.w500, color: p.onBrand.withValues(alpha: enabled ? 1 : 0.85))),
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
    // On iPhone: the real UISegmentedControl (iOS 26 Liquid Glass thumb, system animation and fonts).
    // The Mac preview has no UIKit, so it keeps the hand-made look below.
    if (Platform.isIOS) {
      final native = CNSegmentedControl(
        labels: [for (final v in values) label(v)],
        selectedIndex: values.indexOf(selected),
        height: height,
        shrinkWrap: !expand,
        onValueChanged: (i) {
          if (values[i] != selected) HapticFeedback.selectionClick();
          onChanged(values[i]);
        },
      );
      return expand ? SizedBox(width: double.infinity, child: native) : native;
    }
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final thumbDecoration = BoxDecoration(
      color: dark ? const Color(0xFF636366) : p.card,
      borderRadius: BorderRadius.circular(99),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6, offset: const Offset(0, 2))],
    );
    void pick(T value) {
      if (value != selected) HapticFeedback.selectionClick();
      onChanged(value);
    }

    Widget labelFor(T value) {
      final on = value == selected;
      return AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: cw(IOSText.subheadline - 1, weight: on ? FontWeight.w600 : FontWeight.w400, color: p.ink),
        child: Text(label(value)),
      );
    }

    final track = BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(99));
    if (expand) {
      // Equal segments: one white thumb that slides between them on a spring (like UISegmentedControl).
      // Only its position springs — the thumb's own look never animates, so an overshoot can't produce
      // an invalid shadow or colour.
      final index = values.indexOf(selected);
      final n = values.length;
      return Container(
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: track,
        child: Stack(children: [
          AnimatedAlign(
            duration: IOSMotion.snappyCurve.duration,
            curve: IOSMotion.snappyCurve,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(widthFactor: 1 / n, heightFactor: 1, child: DecoratedBox(decoration: thumbDecoration)),
          ),
          Row(children: [
            for (final v in values)
              Expanded(
                child: Pressable(
                  selected: v == selected,
                  onTap: () => pick(v),
                  child: SizedBox.expand(child: Center(child: labelFor(v))),
                ),
              ),
          ]),
        ]),
      );
    }

    // Hug-content segments (different widths): the thumb fades between segments, with no overshoot.
    Widget item(T value) {
      final on = value == selected;
      return Pressable(
        selected: on,
        onTap: () => pick(value),
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              opacity: on ? 1 : 0,
              child: DecoratedBox(decoration: thumbDecoration),
            ),
          ),
          Container(height: height - 4, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, child: labelFor(value)),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: track,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < values.length; i++) ...[if (i > 0) const SizedBox(width: 2), item(values[i])]
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
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          // Trackly-style bill icon: the bill's own picture in a dashed ring, its parent category as a
          // small badge. Transfers and the like put their line icon in the same ring.
          if (category != null && (entry.kind == EntryKind.expense || entry.kind == EntryKind.income))
            BillIcon(
              badge: category.parentID == null ? null : store.ledger.categoryByID(category.parentID!),
              child: CategoryIcon(category, size: 26, color: tint),
            )
          else
            BillIcon(child: LIcon(icon, size: 19, color: tint)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: cw(IOSText.body, color: p.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 2),
                // Second line (note / payee / date): 14 pt, a step under the 17 pt title.
                Text(details.join(' · '),
                    style: cw(14, color: entry.needsReview ? p.over : p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ]),
          ),
          const SizedBox(width: 10),
          // Bill amounts in the system font, like the rest of the row (only headline totals keep the
          // rounded brand numerals).
          AmountText(entry.amount, size: IOSText.body, weight: FontWeight.w600, sign: sign, color: amountColor, brand: false),
        ]),
      ),
    );
    return SwipeToDelete(key: ValueKey(entry.id), onDelete: () => StoreScope.read(context).deleteEntry(entry), child: row);
  }
}

/// A bill's icon, after Trackly 得意記: the picture centred in a light dashed ring, with an optional
/// small round badge at the lower left showing the parent category on a pale tint of its colour.
class BillIcon extends StatelessWidget {
  const BillIcon({super.key, required this.child, this.badge, this.size = 46});
  final Widget child;
  final LedgerCategory? badge;
  final double size;

  /// Where a row's text starts after this icon (icon + 12 pt gap); row separators inset to it.
  static const double textInset = 58;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final badge = this.badge;
    const badgeSize = 22.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: CustomPaint(painter: _DashedRingPainter(p.muted.withValues(alpha: 0.38)))),
        Center(child: child),
        if (badge != null)
          Positioned(
            left: -4,
            bottom: -4,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                // Opaque, so the ring doesn't show through; a card-coloured rim lifts it off the ring.
                color: Color.alphaBlend(categoryTint(badge.id).withValues(alpha: 0.22), p.card),
                shape: BoxShape.circle,
                border: Border.all(color: p.card, width: 1.5),
              ),
              alignment: Alignment.center,
              child: CategoryIcon(badge, size: 13.5),
            ),
          ),
      ]),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final radius = size.shortestSide / 2 - 0.6;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    // About 22 dashes around the ring, each a little longer than its gap.
    const dashes = 22;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRingPainter old) => old.color != color;
}

/// iOS-style swipe action: drag left to reveal a red 删除 button beside the amount (the row's left side
/// stays in place) (tap it, or keep swiping all
/// the way, to delete). Only one row is open at a time. Rows take every horizontal drag, so swiping
/// over the bill list never switches tabs; that only happens outside the list.
class SwipeToDelete extends StatefulWidget {
  const SwipeToDelete({super.key, required this.child, required this.onDelete});
  final Widget child;
  final VoidCallback onDelete;

  @override
  State<SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<SwipeToDelete> with TickerProviderStateMixin {
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
    _shatter.dispose();
    super.dispose();
  }

  /// Delete animation, "dust" style: the row is captured as an image and dissolves into small
  /// particles, sweeping from left to right; each grain drifts up and to the right, shrinks and fades.
  /// Then the gap it leaves closes, and only then is the bill removed.
  late final AnimationController _shatter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _shattering = false;
  final GlobalKey _rowKey = GlobalKey();
  ui.Image? _snapshot;
  Size _rowSize = Size.zero;
  double _pixelRatio = 1;
  List<_Grain> _grains = const [];

  /// Grain size in points: small enough to read as dust, large enough to stay cheap (~3k grains).
  static const double _grain = 3;

  void _makeGrains(Size size) {
    final random = math.Random(widget.key.hashCode);
    final cols = (size.width / _grain).ceil(), rows = (size.height / _grain).ceil();
    _grains = [
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++)
          _Grain(
            Offset(c * _grain, r * _grain),
            // Left edge goes first; a little jitter so the front is ragged, like sand.
            delay: c / cols * 0.55 + random.nextDouble() * 0.12,
            drift: Offset(18 + random.nextDouble() * 46, -14 - random.nextDouble() * 34),
            spin: (random.nextDouble() - 0.5) * 3,
          ),
    ];
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

  Future<void> _delete() async {
    HapticFeedback.mediumImpact();
    if (_openRow.value == this) _openRow.value = null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Back to full width (button gone), let that frame paint, then photograph the row.
    _offset.value = 0;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ui.Image? image;
    final boundary = _rowKey.currentContext?.findRenderObject();
    if (!reduce && boundary is RenderRepaintBoundary && boundary.hasSize) {
      try {
        _rowSize = boundary.size;
        image = await boundary.toImage(pixelRatio: _pixelRatio);
        _makeGrains(_rowSize);
      } catch (_) {
        image = null; // falls back to a plain fade
      }
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _snapshot = image;
      _shattering = true;
    });
    _shatter.duration = Duration(milliseconds: image == null ? 220 : 900);
    await _shatter.forward(from: 0);
    widget.onDelete();
    _snapshot?.dispose();
    _snapshot = null;
    if (mounted) {
      _shatter.value = 0;
      setState(() => _shattering = false);
    }
  }

  Widget _shattered() {
    final image = _snapshot;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _shatter,
        builder: (context, _) {
          final t = _shatter.value;
          // The last ~30 % closes the gap.
          final collapse = Curves.easeInOut.transform(((t - 0.7) / 0.3).clamp(0.0, 1.0));
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1 - collapse,
              child: image == null
                  ? Opacity(opacity: (1 - t * 1.4).clamp(0.0, 1.0), child: widget.child)
                  : SizedBox.fromSize(
                      size: _rowSize,
                      child: CustomPaint(painter: _DustPainter(image, _grains, t / 0.75, _pixelRatio, _grain)),
                    ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (_shattering) return _shattered();
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
              // The row's right edge pulls in by the revealed width, so the icon and title stay put and
              // only the amount (right-aligned) moves left beside the button; a long title ellipsises.
              // Only when deleting, past the open + stretch range, does the whole row slide away.
              final squeeze = math.min(reveal, _actionWidth + _maxStretch);
              final slide = reveal - squeeze;
              return Stack(children: [
                if (reveal > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => _delete(),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: reveal,
                          padding: EdgeInsets.only(left: math.min(_gap, reveal)),
                          child: Container(
                          decoration: BoxDecoration(color: p.over, borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: reveal > 60
                              ? Column(mainAxisSize: MainAxisSize.min, children: [
                                  const LIcon('trash', size: 18, color: Colors.white),
                                  const SizedBox(height: 2),
                                  Text(tr('删除'), style: cw(IOSText.footnote, weight: FontWeight.w500, color: Colors.white)),
                                ])
                              : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(-slide, 0),
                  child: Padding(padding: EdgeInsets.only(right: squeeze), child: RepaintBoundary(key: _rowKey, child: child)),
                ),
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

/// iOS hairline separator between list rows, inset to where the text starts (past the icon).
class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = BillIcon.textInset});
  final double indent;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(left: indent), child: Divider(height: 0.5, thickness: 0.5, color: Palette.of(context).cardStroke));
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
          style: cw(IOSText.footnote, color: p.muted)),
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
      Text('${currency.name} ${currency.code}', style: cw(IOSText.body, color: color ?? Palette.of(context).muted)),
    ]);
  }
}

/// Empty state in the style of iOS's ContentUnavailableView: a large grey SF-style symbol, a semibold
/// title and a grey description, centred; an optional small grey capsule action under it.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, this.illustration, this.message, this.actionLabel, this.onAction, this.bleed = 0, this.bleedBottom = 0, this.alignment = Alignment.center});

  /// Where the content sits when the state is given more height than it needs (e.g. filling a card).
  final Alignment alignment;

  /// How far the dotted grid runs on below the state (down to the card's bottom edge).
  final double bleedBottom;

  /// How far the dotted grid reaches past the state's own sides, out to the card's edges when the
  /// state sits inside a padded list.
  final double bleed;

  /// Kept for callers: picks the symbol ('receipt' → a document, 'search' → magnifier, 'wallet' → pie chart).
  /// The old coloured illustrations in assets/illustrations are no longer drawn.
  final String? illustration;

  /// Icon name (see [LIcon]); used when there is no [illustration].
  final String icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  static const Map<String, String> _symbolFor = {'receipt': 'receipt', 'search': 'search', 'wallet': 'chart-pie'};

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final symbol = illustration == null ? icon : (_symbolFor[illustration] ?? icon);
    final dotColor = (dark ? Colors.white : Colors.black).withValues(alpha: 0.16);
    // Two companion cards fan out beside the state's own symbol (never duplicating it).
    final companions = ['chart-pie', 'calendar', 'receipt'].where((i) => i != symbol).take(2).toList();

    // Three shades of the same ink, like a printed illustration: the left card darkest, the front
    // one lighter, the right one in between.
    Widget fannedCard(String iconName, {required double rotate, required Offset shift, required double shade}) => Transform.translate(
          offset: shift,
          child: Transform.rotate(
            angle: rotate,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.cardStroke, width: 1),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Center(child: LIcon(iconName, size: 25, color: p.ink.withValues(alpha: shade), strokeWidth: 1.8)),
            ),
          ),
        );

    // The dots cover the whole state (give it the full card: no card padding around it), and the
    // content is centred across the full width.
    // Centred: given a fixed height (e.g. filling a card), the content sits in the middle of the dots.
    return Stack(clipBehavior: Clip.none, alignment: alignment, children: [
        // Dotted grid, like a blank canvas waiting to be filled.
        Positioned(left: -bleed, right: -bleed, top: 0, bottom: -bleedBottom, child: IgnorePointer(child: CustomPaint(painter: _DotGridPainter(dotColor)))),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
          child: SizedBox(
          width: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              height: 84,
              // Each time the state appears the stack deals itself out, driven by real springs (the
              // iOS / SwiftUI `Spring(duration:bounce:)` model) rather than easing curves: the front
              // card pops; the side cards shoot out from behind it upright, overshoot and settle, a
              // quick squash-and-stretch on their scale; then, a beat later, they lean into their
              // tilt on a softer spring. The right card trails the left by 50 ms.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: _EmptyFan.total,
                builder: (context, t, _) {
                  final ms = t * _EmptyFan.total.inMilliseconds;
                  Widget side(String icon, double dir, double shade, double delay) {
                    final out = t >= 1 ? 1.0 : _EmptyFan.at(_EmptyFan.out, ms - delay);
                    final grow = t >= 1 ? 1.0 : _EmptyFan.at(_EmptyFan.grow, ms - delay);
                    final lean = t >= 1 ? 1.0 : _EmptyFan.at(_EmptyFan.lean, ms - delay - 140);
                    return Transform.scale(
                      scale: 0.6 + 0.4 * grow,
                      child: fannedCard(icon, rotate: 0.18 * dir * lean, shift: Offset(40 * dir * out, -4 + 12 * out), shade: shade),
                    );
                  }

                  final pop = t >= 1 ? 1.0 : _EmptyFan.at(_EmptyFan.pop, ms);
                  return Stack(alignment: Alignment.center, children: [
                    side(companions[0], -1, 1.0, 60),
                    side(companions[1], 1, 0.72, 110),
                    Transform.scale(
                      scale: 0.82 + 0.18 * pop,
                      child: fannedCard(symbol, rotate: 0, shift: const Offset(0, -4), shade: 0.6),
                    ),
                  ]);
                },
              ),
            ),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: cw(IOSText.headline, weight: FontWeight.w600, color: p.ink)),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(message!, textAlign: TextAlign.center, style: cw(IOSText.subheadline, color: p.muted, height: 1.35)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              Pressable(
                onTap: onAction,
                semanticLabel: actionLabel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF2C2C2E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.cardStroke, width: 1),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    LIcon('plus', size: 15, color: p.ink),
                    const SizedBox(width: 6),
                    Text(actionLabel!, style: cw(IOSText.subheadline, weight: FontWeight.w600, color: p.ink)),
                  ]),
                ),
              ),
            ],
          ]),
          ),
        ),
      ]);
  }
}

/// Springs for [EmptyState]'s card fan (SwiftUI-style perceptual springs: duration, bounce).
/// Higher bounce than the app's UI springs on purpose — this is a playful flourish.
class _EmptyFan {
  static final SpringDescription pop = IOSMotion.spring(0.42, 0.45);
  static final SpringDescription out = IOSMotion.spring(0.5, 0.42);
  static final SpringDescription grow = IOSMotion.spring(0.4, 0.5);
  static final SpringDescription lean = IOSMotion.spring(0.6, 0.35);
  static const Duration total = Duration(milliseconds: 1000);

  /// Position (0 → 1) of [spring] released from rest, [ms] milliseconds in.
  static double at(SpringDescription spring, double ms) =>
      ms <= 0 ? 0 : SpringSimulation(spring, 0, 1, 0).x(ms / 1000);
}

/// The empty state's dotted-grid backdrop: a quiet lattice of 1 pt dots on a 16 pt pitch.
class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 16.0;
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

/// One grain of a deleted row: where it sits, when it lets go (0…~0.67 of the dissolve), where it
/// drifts and how it turns.
class _Grain {
  const _Grain(this.origin, {required this.delay, required this.drift, required this.spin});
  final Offset origin;
  final double delay;
  final Offset drift;
  final double spin;
}

/// Draws the row snapshot as grains with one drawAtlas call per frame: each grain, once released,
/// drifts up-right, spins, shrinks and fades. [progress] runs 0 → 1 (values past 1 are clamped).
class _DustPainter extends CustomPainter {
  _DustPainter(this.image, this.grains, this.progress, this.pixelRatio, this.grain);
  final ui.Image image;
  final List<_Grain> grains;
  final double progress;
  final double pixelRatio;
  final double grain;

  @override
  void paint(Canvas canvas, Size size) {
    final transforms = <RSTransform>[];
    final rects = <Rect>[];
    final colors = <Color>[];
    final t = progress.clamp(0.0, 1.0);
    final half = grain / 2;
    for (final g in grains) {
      final local = ((t - g.delay) / 0.33).clamp(0.0, 1.0);
      if (local >= 1) continue;
      final e = Curves.easeOut.transform(local);
      final alpha = 1 - Curves.easeIn.transform(local);
      if (alpha <= 0.01) continue;
      final scale = (1 - 0.6 * e) / pixelRatio;
      final centre = g.origin + Offset(half, half) + g.drift * e;
      transforms.add(RSTransform.fromComponents(
        rotation: g.spin * e,
        scale: scale,
        anchorX: half * pixelRatio,
        anchorY: half * pixelRatio,
        translateX: centre.dx,
        translateY: centre.dy,
      ));
      rects.add(Rect.fromLTWH(g.origin.dx * pixelRatio, g.origin.dy * pixelRatio, grain * pixelRatio, grain * pixelRatio));
      colors.add(Color.fromRGBO(255, 255, 255, alpha));
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(image, transforms, rects, colors, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low);
  }

  @override
  bool shouldRepaint(covariant _DustPainter old) => old.progress != progress || old.image != image;
}

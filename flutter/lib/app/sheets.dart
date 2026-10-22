import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components.dart';
import 'icons.dart';
import 'motion.dart';
import 'theme.dart';
import '../l10n/l10n.dart';

/// Opens [builder] as a Copilot-style sheet: rounded top, grabber, canvas background, near full height.
///
/// With [guarded], swiping the sheet down asks the route to pop (Navigator.maybePop) instead of closing
/// it outright, so a PopScope inside — e.g. "放弃本次修改？" in the entry editor — can keep it open.
/// Flutter's own drag-to-dismiss pops directly and would skip that check.
Future<T?> showCwSheet<T>(BuildContext context, WidgetBuilder builder, {bool guarded = false}) {
  final p = Palette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: !guarded,
    backgroundColor: p.canvas,
    barrierColor: const Color(0x59000000),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    clipBehavior: Clip.antiAlias,
    // iOS sheets rise and fall on a smooth (no-bounce) spring.
    sheetAnimationStyle: AnimationStyle(
      duration: IOSMotion.smoothCurve.duration,
      curve: IOSMotion.smoothCurve,
      reverseDuration: IOSMotion.smoothCurve.duration,
      reverseCurve: IOSMotion.smoothCurve.flipped,
    ),
    // Paint the canvas inside the sheet too, so it follows a theme change made while the sheet is open.
    builder: (context) {
      final content = ColoredBox(color: Palette.of(context).canvas, child: builder(context));
      return FractionallySizedBox(heightFactor: 0.94, child: guarded ? _DragToClose(child: content) : content);
    },
  );
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
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(tr('放弃本次修改？')),
      content: Text(tr('已输入的内容不会保存。')),
      actions: [
        CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.of(context).pop(false), child: Text(tr('继续编辑'))),
        CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.of(context).pop(true), child: Text(tr('放弃修改'))),
      ],
    ),
  );
  return result ?? false;
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
  });

  final String title;
  final Widget body;
  final String? leadingLabel;
  final VoidCallback? onLeading;
  final String? trailingLabel;
  final VoidCallback? onTrailing;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(children: [
      const SizedBox(height: 8),
      Container(width: 38, height: 5, decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(9))),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: SizedBox(
          height: 36,
          child: Stack(alignment: Alignment.center, children: [
            Text(title, style: cw(15, weight: FontWeight.w600, color: p.ink)),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: onLeading ?? () => Navigator.of(context).maybePop(),
                child: Text(leadingLabel ?? tr('取消'), style: cw(16, weight: FontWeight.w400, color: p.accent)),
              ),
            ),
            if (trailingLabel != null)
              Align(
                alignment: Alignment.centerRight,
                child: Pressable(
                  onTap: onTrailing,
                  child: Text(trailingLabel!,
                      style: cw(16, weight: FontWeight.w700, color: onTrailing == null ? p.muted : p.accent)),
                ),
              ),
          ]),
        ),
      ),
      Expanded(child: body),
      if (bottom != null) bottom!,
    ]);
  }
}

/// iOS-style alert with one dismiss button.
Future<void> showCwAlert(BuildContext context, String title, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.of(context).pop(), child: Text(tr('知道了')))],
    ),
  );
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

/// Grouped settings-style section: small caption above a white card of rows.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.title, required this.children, this.footer});
  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: CardCaption(title!)),
      CwCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.track),
            children[i],
          ]
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(footer!, style: cw(12, color: p.muted, height: 1.45)),
        ),
    ]);
  }
}

/// One row in a [FormSection]: optional icon, label, trailing widget; tappable when [onTap] is set.
class FormRow extends StatelessWidget {
  const FormRow({super.key, this.icon, required this.label, this.trailing, this.onTap, this.destructive = false, this.chevron = false});
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
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        if (icon != null) ...[LIcon(icon!, size: 17, color: destructive ? p.over : p.muted), const SizedBox(width: 10)],
        Expanded(child: Text(label, style: cw(15, weight: FontWeight.w400, color: color))),
        if (trailing != null) trailing!,
        if (chevron) ...[const SizedBox(width: 4), LIcon('chevron-right', size: 16, color: p.muted.withValues(alpha: 0.7))],
      ]),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
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
      this.inputFormatters});
  final List<TextInputFormatter>? inputFormatters;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final TextAlign textAlign;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: 1,
      textAlign: textAlign,
      autocorrect: false,
      inputFormatters: inputFormatters,
      style: cw(15, weight: FontWeight.w400, color: p.ink),
      decoration: InputDecoration(hintText: hint, contentPadding: const EdgeInsets.symmetric(vertical: 14)),
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
              Expanded(child: Text(label(option), style: cw(15, weight: FontWeight.w400, color: p.ink))),
              if (option == value) LIcon('check', size: 16, color: p.accent),
            ]),
          ),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(value == null ? placeholder ?? tr('请选择') : label(value as T),
              style: cw(15, weight: FontWeight.w600, color: p.accent), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 4),
        LIcon('chevron-down', size: 16, color: p.accent),
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
      Row(children: [
        LIcon(icon, size: 17, color: p.muted),
        const SizedBox(width: 10),
        Text(label, style: cw(15, color: p.ink)),
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
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: 27, bottom: 10),
          child: Text(error!, style: cw(12, color: p.over)),
        ),
    ]);
  }
}

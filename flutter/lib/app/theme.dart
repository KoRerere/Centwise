import 'package:flutter/material.dart';

import '../core/models.dart';

/// Centwise visual language: monochrome minimal (reference: Trackly 得意記 onboarding).
/// Black and white do the work; hierarchy comes from size and weight, not colour. A plain white
/// header (no colour wash), white cards with a hairline border (no shadow), near-black ink, black
/// capsule buttons. Colour is kept only where it carries meaning: income green, over-budget red,
/// category emoji and the category chart slices.
class Palette {
  const Palette({
    required this.brand,
    required this.onBrand,
    required this.brandDeep,
    required this.accent,
    required this.canvas,
    required this.card,
    required this.cardStroke,
    required this.ink,
    required this.muted,
    required this.track,
    required this.income,
    required this.under,
    required this.warning,
    required this.over,
  });

  final Color brand;
  /// Text / icons drawn on top of [brand] (white in light mode, black in dark mode).
  final Color onBrand;
  final Color brandDeep;
  final Color accent;
  final Color canvas;
  final Color card;
  final Color cardStroke;
  final Color ink;
  final Color muted;
  final Color track;
  final Color income;
  final Color under;
  final Color warning;
  final Color over;

  static Color _rgb(double r, double g, double b) =>
      Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round());

  static final Palette light = Palette(
    // Near-black brand: buttons, selected states, expense bars. No blue anywhere.
    brand: const Color(0xFF0A0A0A),
    onBrand: const Color(0xFFFFFFFF),
    brandDeep: const Color(0xFF0A0A0A),
    accent: const Color(0xFF0A0A0A),
    canvas: const Color(0xFFFFFFFF),
    card: const Color(0xFFFFFFFF),
    cardStroke: const Color(0xFFE8E8EA),
    ink: const Color(0xFF0A0A0A),
    muted: const Color(0xFF8E8E93),
    track: const Color(0xFFF0F0F2),
    income: _rgb(0.15, 0.60, 0.27),
    under: _rgb(0.25, 0.70, 0.30),
    warning: _rgb(0.95, 0.60, 0.16),
    over: _rgb(0.86, 0.20, 0.20),
  );

  static final Palette dark = Palette(
    // Inverted: white capsules with black text on a true-black canvas.
    brand: const Color(0xFFF5F5F5),
    onBrand: const Color(0xFF0A0A0A),
    brandDeep: const Color(0xFFF5F5F5),
    accent: const Color(0xFFF5F5F5),
    canvas: const Color(0xFF000000),
    card: const Color(0xFF111111),
    cardStroke: const Color(0xFF26262A),
    ink: const Color(0xFFF5F5F5),
    muted: const Color(0xFF8E8E93),
    track: const Color(0xFF1F1F22),
    income: _rgb(0.36, 0.84, 0.46),
    under: _rgb(0.36, 0.84, 0.46),
    warning: _rgb(1.00, 0.68, 0.28),
    over: _rgb(1.00, 0.38, 0.36),
  );

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;

  Color kindColor(EntryKind kind) => switch (kind) {
        EntryKind.income => income,
        EntryKind.expense => ink,
        EntryKind.transfer => accent,
        EntryKind.adjustment => muted,
      };

  /// Budget bar colour: green while comfortably under, orange near the limit, red when over.
  Color budgetColor(double ratio) => ratio >= 1 ? over : (ratio >= 0.8 ? warning : under);

  /// The header is plain canvas now (no colour wash); kept as a flat gradient so callers still compile.
  LinearGradient get headerGradient => LinearGradient(colors: [canvas, canvas]);
}

/// Categories carry no stored colour, so derive a stable one from the id (same formula as the SwiftUI version).
Color categoryTint(String id) {
  var seed = 0;
  for (final unit in id.runes) {
    seed = (seed * 31 + unit) & 0x7fffffff;
  }
  return categoryPalette[seed % categoryPalette.length];
}

/// Apple's iOS system colours (Human Interface Guidelines), light-mode values. Red is left out: it means
/// "over budget" here.
const List<Color> categoryPalette = [
  Color(0xFF007AFF), // systemBlue
  Color(0xFFFF9500), // systemOrange
  Color(0xFF34C759), // systemGreen
  Color(0xFFAF52DE), // systemPurple
  Color(0xFF30B0C7), // systemTeal
  Color(0xFFFF2D55), // systemPink
  Color(0xFF5856D6), // systemIndigo
  Color(0xFFFFCC00), // systemYellow
  Color(0xFF00C7BE), // systemMint
  Color(0xFF32ADE6), // systemCyan
];

/// Nunito is kept for the Centwise logo and money amounts only; everything else uses the system font
/// (San Francisco + PingFang on iPhone and Mac).
const String brandFontFamily = 'Nunito';

ThemeData buildTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: palette.brand, brightness: brightness, dynamicSchemeVariant: DynamicSchemeVariant.monochrome).copyWith(
      primary: palette.accent,
      onPrimary: palette.onBrand,
      surface: palette.canvas,
      onSurface: palette.ink,
      error: palette.over,
    ),
    scaffoldBackgroundColor: palette.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: palette.track,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: palette.ink, displayColor: palette.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: palette.muted),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? palette.ink : palette.track),
      thumbColor: WidgetStatePropertyAll(brightness == Brightness.dark ? palette.canvas : Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      border: InputBorder.none,
      hintStyle: TextStyle(color: palette.muted, fontWeight: FontWeight.w400),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: palette.accent),
  );
}

/// Shorthand for the rounded text style used everywhere.
TextStyle cw(double size, {FontWeight weight = FontWeight.w400, Color? color, double? spacing, double? height, bool brand = false}) =>
    TextStyle(
        // Name the system font outright: left to the default, a line that mixes digits with Chinese
        // (e.g. "2026年10月") could pick PingFang's digits. San Francisco first, PingFang for Chinese.
        fontFamily: brand ? brandFontFamily : (size >= 20 ? 'CupertinoSystemDisplay' : 'CupertinoSystemText'),
        fontFamilyFallback: brand ? null : const ['PingFang SC', 'PingFang TC'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: spacing,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()]);

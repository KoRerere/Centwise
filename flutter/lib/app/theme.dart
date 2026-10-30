import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';

/// Centwise visual language: monochrome, following iOS conventions (reference: Trackly 得意記 for the
/// black-and-white look, Apple's own apps for structure). iOS "inset grouped" surfaces: a light grey
/// systemGroupedBackground canvas with plain white cards (no border, no shadow), near-black ink, iOS
/// secondary-label grey, hairline separators and black capsule buttons. Colour is kept only where it
/// carries meaning: income green, over-budget red, category emoji and the category chart slices.
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
    // iOS systemGroupedBackground / secondarySystemGroupedBackground, separator and systemGray5.
    canvas: const Color(0xFFF2F2F7),
    card: const Color(0xFFFFFFFF),
    cardStroke: const Color(0xFFD9D9DE),
    ink: const Color(0xFF0A0A0A),
    muted: const Color(0xFF8A8A8E),
    track: const Color(0xFFE5E5EA),
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
    // iOS dark grouped colours: black canvas, #1C1C1E cards, #38383A separators, systemGray5.
    canvas: const Color(0xFF000000),
    card: const Color(0xFF1C1C1E),
    cardStroke: const Color(0xFF38383A),
    ink: const Color(0xFFF5F5F5),
    muted: const Color(0xFF8D8D93),
    track: const Color(0xFF2C2C2E),
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

/// Apple's iOS system colours (Human Interface Guidelines), light-mode values, without the blues (the
/// app is monochrome; blue read as the old brand colour) and without red (it means "over budget").
const List<Color> categoryPalette = [
  Color(0xFFFF9500), // systemOrange
  Color(0xFF34C759), // systemGreen
  Color(0xFFAF52DE), // systemPurple
  Color(0xFFFF2D55), // systemPink
  Color(0xFFFFCC00), // systemYellow
  Color(0xFF00C7BE), // systemMint
  Color(0xFFA2845E), // systemBrown
  Color(0xFF8E8E93), // systemGray
  Color(0xFF636366), // systemGray2 (dark)
  Color(0xFFFF6482), // pink, lighter
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
    dividerColor: palette.cardStroke,
    // iOS everywhere: rubber-band scrolling and push transitions that slide in from the right (with the
    // edge-swipe back gesture), on the Mac preview too.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    }),
    cupertinoOverrideTheme: CupertinoThemeData(primaryColor: palette.accent, brightness: brightness),
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

/// iOS text styles (Dynamic Type "Large" sizes), so every screen draws from one scale instead of
/// one-off sizes: use these with [cw], e.g. cw(IOSText.body).
abstract final class IOSText {
  static const double largeTitle = 34;
  static const double title1 = 28;
  static const double title2 = 22;
  static const double title3 = 20;
  static const double headline = 17; // semibold
  static const double body = 17;
  static const double callout = 16;
  static const double subheadline = 15;
  static const double footnote = 13;
  static const double caption1 = 12;
  static const double caption2 = 11;
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
        letterSpacing: spacing ?? (brand ? null : iosTracking(size)),
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()]);

/// Apple's system-font tracking for a point size (HIG type scale: 17 pt → −0.43, 13 pt → −0.08,
/// 28 pt → +0.38 …). iOS applies it to all system text, Chinese included — that is why 17 pt labels in
/// Settings sit tighter than plain 17 pt PingFang. Flutter doesn't do this on its own.
double iosTracking(double size) {
  const table = <(double, double)>[
    (11, 0.06), (12, 0), (13, -0.08), (14, -0.15), (15, -0.23), (16, -0.31), (17, -0.43),
    (20, -0.45), (22, -0.26), (28, 0.38), (34, 0.40),
  ];
  if (size <= table.first.$1) return table.first.$2;
  if (size >= table.last.$1) return table.last.$2;
  for (var i = 1; i < table.length; i++) {
    final (s1, t1) = table[i];
    if (size <= s1) {
      final (s0, t0) = table[i - 1];
      return t0 + (t1 - t0) * (size - s0) / (s1 - s0);
    }
  }
  return 0;
}

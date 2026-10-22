/// Money is integer fen (cents), never a binary floating-point value.
library;

import '../l10n/l10n.dart';

class LedgerError implements Exception {
  LedgerError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Money {
  Money._();

  static const int maximum = 9000000000000;

  static final RegExp _inputPattern = RegExp(r'^-?[0-9]+(?:\.[0-9]{1,2})?$');

  /// Parses user input such as "12.34" or "-26.14". At most two decimals, no grouping separators.
  static int parse(String text) {
    final normalized = text.trim();
    if (!_inputPattern.hasMatch(normalized)) {
      throw LedgerError(tr('请输入金额，最多保留两位小数，不要使用千位分隔符。'));
    }
    return _cents(normalized, allowStorageNoise: false);
  }

  /// SQLite REAL is read as text first; tolerate only representation noise below 1/10000 fen.
  static int legacy(String text) {
    try {
      return _cents(text.trim(), allowStorageNoise: true);
    } on FormatException {
      throw LedgerError(tr('旧账本含有无法识别的金额。'));
    }
  }

  static final RegExp _decimalPattern = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

  static int _cents(String text, {required bool allowStorageNoise}) {
    final match = _decimalPattern.firstMatch(text);
    if (match == null || ((match.group(2) ?? '').isEmpty && (match.group(3) ?? '').isEmpty)) {
      throw const FormatException('not a decimal');
    }
    final negative = match.group(1) == '-';
    final whole = match.group(2) ?? '';
    final fraction = match.group(3) ?? '';
    final exponent = int.parse(match.group(4) ?? '0');
    // value = digits × 10^(exponent − fraction.length); cents = value × 100.
    var digits = BigInt.parse('${whole.isEmpty ? '0' : whole}$fraction');
    if (negative) digits = -digits;
    final shift = exponent - fraction.length + 2;
    final BigInt rounded;
    if (shift >= 0) {
      rounded = digits * BigInt.from(10).pow(shift);
    } else {
      final denominator = BigInt.from(10).pow(-shift);
      final quotient = digits ~/ denominator; // truncates toward zero
      final remainder = digits - quotient * denominator;
      // Round half away from zero (Foundation's .plain rounding).
      final roundAway = remainder.abs() * BigInt.two >= denominator;
      final candidate = roundAway ? quotient + BigInt.from(digits.isNegative ? -1 : 1) : quotient;
      final difference = (digits - candidate * denominator).abs();
      final ok = allowStorageNoise
          ? difference * BigInt.from(10000) <= denominator
          : difference == BigInt.zero;
      if (!ok) throw LedgerError(tr('金额超出范围，或含有超过两位小数的有效精度。'));
      rounded = candidate;
    }
    if (rounded.abs() > BigInt.from(maximum)) {
      throw LedgerError(tr('金额超出范围，或含有超过两位小数的有效精度。'));
    }
    return rounded.toInt();
  }

  /// Symbol of the ledger's currency (see core/currency.dart); the app keeps it in step with the ledger.
  static String symbol = '¥';

  /// "¥1,234.56" / "-¥1,234.56", or "1,234.56" without the symbol.
  static String text(int cents, {bool symbol = true}) {
    final negative = cents < 0;
    final magnitude = cents.abs();
    final whole = (magnitude ~/ 100).toString();
    final fraction = (magnitude % 100).toString().padLeft(2, '0');
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
      grouped.write(whole[i]);
    }
    return '${negative ? '-' : ''}${symbol ? Money.symbol : ''}$grouped.$fraction';
  }

  /// Plain editable form without trailing zeros: 1230 → "12.3", -2614 → "-26.14", 0 → "0".
  static String input(int cents) {
    final negative = cents < 0;
    final magnitude = cents.abs();
    final whole = magnitude ~/ 100;
    var fraction = (magnitude % 100).toString().padLeft(2, '0');
    while (fraction.endsWith('0')) {
      fraction = fraction.substring(0, fraction.length - 1);
    }
    final body = fraction.isEmpty ? '$whole' : '$whole.$fraction';
    return negative && magnitude != 0 ? '-$body' : body;
  }
}

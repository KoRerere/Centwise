// Centwise UI language.
//
// Strings are written in Simplified Chinese where they are used, e.g. `tr('已支出')`, and looked up
// here for Traditional Chinese (Taiwan) and English; anything missing falls back to the source text.
// Placeholders use `{name}`: `tr('{n} 笔', {'n': 3})`. An English value written as `one|other`
// picks the singular form when `n == 1`. The same Chinese word that needs different English in
// different places takes a context: `tr('近一年', ctx: 'period')` looks up `近一年@period`.
//
// Pure Dart (no Flutter import) so that lib/core can use it too.
import 'l10n_tables.dart';

/// A UI language Centwise is translated into.
enum Lang { zhHans, zhHant, en }

/// 设置 → 语言: follow the device, or one fixed language.
enum LanguagePref { system, zhHans, zhHant, en }

class L10n {
  L10n._();

  /// The language currently shown. Set by LedgerStore from the saved preference.
  static Lang current = Lang.zhHans;

  static bool get isEnglish => current == Lang.en;

  /// Resolves the preference against the device locale: Chinese in Taiwan / Hong Kong / Macau or
  /// written in Hant script → Traditional; any other Chinese → Simplified; everything else → English.
  static Lang resolve(LanguagePref pref, {required String languageCode, String? scriptCode, String? countryCode}) {
    switch (pref) {
      case LanguagePref.zhHans:
        return Lang.zhHans;
      case LanguagePref.zhHant:
        return Lang.zhHant;
      case LanguagePref.en:
        return Lang.en;
      case LanguagePref.system:
        if (languageCode != 'zh') return Lang.en;
        if (scriptCode == 'Hant') return Lang.zhHant;
        if (scriptCode == 'Hans') return Lang.zhHans;
        return const {'TW', 'HK', 'MO'}.contains(countryCode) ? Lang.zhHant : Lang.zhHans;
    }
  }
}

/// Translates [source] (Simplified Chinese) into the current language.
String tr(String source, [Map<String, Object?> args = const {}, String? ctx]) {
  final key = ctx == null ? source : '$source@$ctx';
  var text = switch (L10n.current) {
    Lang.zhHans => source,
    Lang.zhHant => zhHantStrings[key] ?? zhHantStrings[source] ?? source,
    Lang.en => enStrings[key] ?? enStrings[source] ?? source,
  };
  if (text.contains('|') && L10n.current == Lang.en) {
    final forms = text.split('|');
    text = args['n'] == 1 ? forms.first : forms.last;
  }
  args.forEach((name, value) => text = text.replaceAll('{$name}', '$value'));
  return text;
}

const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _enWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _zhWeekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

/// 10月14日 · Oct 14
String fmtMonthDay(DateTime d) => L10n.isEnglish ? '${_enMonths[d.month - 1]} ${d.day}' : '${d.month}月${d.day}日';

/// 2026年10月14日 · Oct 14, 2026
String fmtYMD(DateTime d) =>
    L10n.isEnglish ? '${_enMonths[d.month - 1]} ${d.day}, ${d.year}' : '${d.year}年${d.month}月${d.day}日';

/// 2026年10月 · Oct 2026
String fmtYearMonth(DateTime d) => L10n.isEnglish ? '${_enMonths[d.month - 1]} ${d.year}' : '${d.year}年${d.month}月';

/// 10月 · Oct
String fmtMonth(DateTime d) => L10n.isEnglish ? _enMonths[d.month - 1] : '${d.month}月';

/// 10月13日 星期二 · Tuesday, Oct 13
String fmtDayHeading(DateTime d) => L10n.isEnglish
    ? '${_enWeekdays[d.weekday - 1]}, ${fmtMonthDay(d)}'
    : '${fmtMonthDay(d)} ${_zhWeekdays[d.weekday - 1]}';

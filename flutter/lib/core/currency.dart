import '../l10n/l10n.dart';

/// A currency the ledger can be kept in. Centwise keeps one currency per ledger and does not convert:
/// changing it only changes the symbol and labels, amounts stay as entered (two decimals).
class Currency {
  const Currency(this.code, this.flag, this.symbol, this.zhHans, this.zhHant, this.en);
  final String code;

  /// Country / region code of the round flag in assets/flags/ (EU for the euro).
  final String flag;
  final String symbol;
  final String zhHans;
  final String zhHant;
  final String en;

  String get name => switch (L10n.current) { Lang.zhHans => zhHans, Lang.zhHant => zhHant, Lang.en => en };
}

const List<Currency> supportedCurrencies = [
  Currency('CNY', 'CN', '¥', '人民币', '人民幣', 'Chinese Yuan'),
  Currency('HKD', 'HK', 'HK\$', '港币', '港幣', 'Hong Kong Dollar'),
  Currency('TWD', 'TW', 'NT\$', '新台币', '新台幣', 'New Taiwan Dollar'),
  Currency('MOP', 'MO', 'MOP\$', '澳门元', '澳門元', 'Macanese Pataca'),
  Currency('USD', 'US', '\$', '美元', '美元', 'US Dollar'),
  Currency('EUR', 'EU', '€', '欧元', '歐元', 'Euro'),
  Currency('GBP', 'GB', '£', '英镑', '英鎊', 'British Pound'),
  Currency('JPY', 'JP', '¥', '日元', '日圓', 'Japanese Yen'),
  Currency('KRW', 'KR', '₩', '韩元', '韓元', 'South Korean Won'),
  Currency('SGD', 'SG', 'S\$', '新加坡元', '新加坡元', 'Singapore Dollar'),
  Currency('MYR', 'MY', 'RM', '马来西亚林吉特', '馬來西亞令吉', 'Malaysian Ringgit'),
  Currency('THB', 'TH', '฿', '泰铢', '泰銖', 'Thai Baht'),
  Currency('VND', 'VN', '₫', '越南盾', '越南盾', 'Vietnamese Dong'),
  Currency('PHP', 'PH', '₱', '菲律宾比索', '菲律賓披索', 'Philippine Peso'),
  Currency('IDR', 'ID', 'Rp', '印尼盾', '印尼盾', 'Indonesian Rupiah'),
  Currency('INR', 'IN', '₹', '印度卢比', '印度盧比', 'Indian Rupee'),
  Currency('AUD', 'AU', 'A\$', '澳元', '澳幣', 'Australian Dollar'),
  Currency('NZD', 'NZ', 'NZ\$', '新西兰元', '紐西蘭元', 'New Zealand Dollar'),
  Currency('CAD', 'CA', 'C\$', '加元', '加幣', 'Canadian Dollar'),
  Currency('CHF', 'CH', 'CHF', '瑞士法郎', '瑞士法郎', 'Swiss Franc'),
  Currency('AED', 'AE', 'AED', '阿联酋迪拉姆', '阿聯酋迪拉姆', 'UAE Dirham'),
  Currency('RUB', 'RU', '₽', '卢布', '盧布', 'Russian Ruble'),
];

Currency currencyFor(String code) =>
    supportedCurrencies.firstWhere((c) => c.code == code, orElse: () => supportedCurrencies.first);

bool isSupportedCurrency(String code) => supportedCurrencies.any((c) => c.code == code);

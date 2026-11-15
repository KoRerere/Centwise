import Foundation

/// A currency the ledger can be kept in. Centwise keeps one currency per ledger and does not convert:
/// changing it only changes the symbol and labels, amounts stay as entered (two decimals).
struct Currency: Hashable {
    let code: String
    /// Region code of the round flag in Assets.xcassets/Flags (EU for the euro).
    let flag: String
    let symbol: String
    let zhHans: String
    let zhHant: String
    let en: String

    var name: String {
        switch L10n.current {
        case .zhHans: zhHans
        case .zhHant: zhHant
        case .en: en
        }
    }
}

let supportedCurrencies: [Currency] = [
    Currency(code: "CNY", flag: "CN", symbol: "¥", zhHans: "人民币", zhHant: "人民幣", en: "Chinese Yuan"),
    Currency(code: "HKD", flag: "HK", symbol: "HK$", zhHans: "港币", zhHant: "港幣", en: "Hong Kong Dollar"),
    Currency(code: "TWD", flag: "TW", symbol: "NT$", zhHans: "新台币", zhHant: "新台幣", en: "New Taiwan Dollar"),
    Currency(code: "MOP", flag: "MO", symbol: "MOP$", zhHans: "澳门元", zhHant: "澳門元", en: "Macanese Pataca"),
    Currency(code: "USD", flag: "US", symbol: "$", zhHans: "美元", zhHant: "美元", en: "US Dollar"),
    Currency(code: "EUR", flag: "EU", symbol: "€", zhHans: "欧元", zhHant: "歐元", en: "Euro"),
    Currency(code: "GBP", flag: "GB", symbol: "£", zhHans: "英镑", zhHant: "英鎊", en: "British Pound"),
    Currency(code: "JPY", flag: "JP", symbol: "¥", zhHans: "日元", zhHant: "日圓", en: "Japanese Yen"),
    Currency(code: "KRW", flag: "KR", symbol: "₩", zhHans: "韩元", zhHant: "韓元", en: "South Korean Won"),
    Currency(code: "SGD", flag: "SG", symbol: "S$", zhHans: "新加坡元", zhHant: "新加坡元", en: "Singapore Dollar"),
    Currency(code: "MYR", flag: "MY", symbol: "RM", zhHans: "马来西亚林吉特", zhHant: "馬來西亞令吉", en: "Malaysian Ringgit"),
    Currency(code: "THB", flag: "TH", symbol: "฿", zhHans: "泰铢", zhHant: "泰銖", en: "Thai Baht"),
    Currency(code: "VND", flag: "VN", symbol: "₫", zhHans: "越南盾", zhHant: "越南盾", en: "Vietnamese Dong"),
    Currency(code: "PHP", flag: "PH", symbol: "₱", zhHans: "菲律宾比索", zhHant: "菲律賓披索", en: "Philippine Peso"),
    Currency(code: "IDR", flag: "ID", symbol: "Rp", zhHans: "印尼盾", zhHant: "印尼盾", en: "Indonesian Rupiah"),
    Currency(code: "INR", flag: "IN", symbol: "₹", zhHans: "印度卢比", zhHant: "印度盧比", en: "Indian Rupee"),
    Currency(code: "AUD", flag: "AU", symbol: "A$", zhHans: "澳元", zhHant: "澳幣", en: "Australian Dollar"),
    Currency(code: "NZD", flag: "NZ", symbol: "NZ$", zhHans: "新西兰元", zhHant: "紐西蘭元", en: "New Zealand Dollar"),
    Currency(code: "CAD", flag: "CA", symbol: "C$", zhHans: "加元", zhHant: "加幣", en: "Canadian Dollar"),
    Currency(code: "CHF", flag: "CH", symbol: "CHF", zhHans: "瑞士法郎", zhHant: "瑞士法郎", en: "Swiss Franc"),
    Currency(code: "AED", flag: "AE", symbol: "AED", zhHans: "阿联酋迪拉姆", zhHant: "阿聯酋迪拉姆", en: "UAE Dirham"),
    Currency(code: "RUB", flag: "RU", symbol: "₽", zhHans: "卢布", zhHant: "盧布", en: "Russian Ruble"),
]

func currencyFor(_ code: String) -> Currency {
    supportedCurrencies.first { $0.code == code } ?? supportedCurrencies[0]
}

func isSupportedCurrency(_ code: String) -> Bool {
    supportedCurrencies.contains { $0.code == code }
}

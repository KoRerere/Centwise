import Foundation

/// A UI language Centwise is translated into.
enum Lang { case zhHans, zhHant, en }

/// 设置 → 语言: follow the device, or one fixed language.
enum LanguagePref: String, CaseIterable { case system, zhHans, zhHant, en }

/// Strings are written in Simplified Chinese where they are used, e.g. `tr("已支出")`, and looked up in
/// L10nTables.swift for Traditional Chinese (Taiwan) and English; anything missing falls back to the
/// source. Placeholders use `{name}`. An English value written as `one|other` picks the singular form
/// when n == 1. Context: `tr("近一年", ctx: "period")` looks up "近一年@period".
enum L10n {
    nonisolated(unsafe) static var current: Lang = .zhHans
    static var isEnglish: Bool { current == .en }

    static func resolve(_ pref: LanguagePref, locale: Locale = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? .current) -> Lang {
        switch pref {
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        case .en: return .en
        case .system:
            guard locale.language.languageCode?.identifier == "zh" else { return .en }
            if let script = locale.language.script?.identifier {
                if script == "Hant" { return .zhHant }
                if script == "Hans" { return .zhHans }
            }
            let region = locale.region?.identifier ?? ""
            return ["TW", "HK", "MO"].contains(region) ? .zhHant : .zhHans
        }
    }

    /// Locale for system controls (date pickers) in the current language.
    static var locale: Locale {
        switch current {
        case .zhHans: Locale(identifier: "zh-Hans-CN")
        case .zhHant: Locale(identifier: "zh-Hant-TW")
        case .en: Locale(identifier: "en")
        }
    }
}

/// Translates `source` (Simplified Chinese) into the current language.
func tr(_ source: String, _ args: [String: Any] = [:], ctx: String? = nil) -> String {
    let key = ctx.map { "\(source)@\($0)" } ?? source
    var text: String
    switch L10n.current {
    case .zhHans: text = source
    case .zhHant: text = zhHantStrings[key] ?? zhHantStrings[source] ?? source
    case .en: text = enStrings[key] ?? enStrings[source] ?? source
    }
    if L10n.current == .en, text.contains("|") {
        let forms = text.components(separatedBy: "|")
        let n = args["n"] as? Int
        text = n == 1 ? forms.first! : forms.last!
    }
    for (name, value) in args { text = text.replacingOccurrences(of: "{\(name)}", with: "\(value)") }
    return text
}

private let enMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
private let enWeekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
private let zhWeekdays = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]

/// 10月14日 · Oct 14
func fmtMonthDay(_ d: Date) -> String {
    let p = Cal.parts(d)
    return L10n.isEnglish ? "\(enMonths[p.month - 1]) \(p.day)" : "\(p.month)月\(p.day)日"
}

/// 2026年10月14日 · Oct 14, 2026
func fmtYMD(_ d: Date) -> String {
    let p = Cal.parts(d)
    return L10n.isEnglish ? "\(enMonths[p.month - 1]) \(p.day), \(p.year)" : "\(p.year)年\(p.month)月\(p.day)日"
}

/// 2026年10月 · Oct 2026
func fmtYearMonth(_ d: Date) -> String {
    let p = Cal.parts(d)
    return L10n.isEnglish ? "\(enMonths[p.month - 1]) \(p.year)" : "\(p.year)年\(p.month)月"
}

/// 10月 · Oct
func fmtMonth(_ d: Date) -> String {
    let p = Cal.parts(d)
    return L10n.isEnglish ? enMonths[p.month - 1] : "\(p.month)月"
}

/// 10月13日 星期二 · Tuesday, Oct 13
func fmtDayHeading(_ d: Date) -> String {
    let w = Cal.parts(d).weekday
    let weekday = L10n.isEnglish ? enWeekdays[w - 1] : (L10n.current == .zhHant ? tr(zhWeekdays[w - 1]) : zhWeekdays[w - 1])
    return L10n.isEnglish ? "\(weekday), \(fmtMonthDay(d))" : "\(fmtMonthDay(d)) \(weekday)"
}

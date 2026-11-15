import Foundation

/// Local-calendar helpers mirroring Dart's DateTime(y, m, d …) constructor, which normalises
/// out-of-range parts (month 13 → January next year, day 0 → last day of the previous month).
enum Cal {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static func date(_ year: Int, _ month: Int, _ day: Int = 1, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        // Normalise month first so day 0 / day overflow is applied to the right month.
        var y = year, m = month
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        var parts = DateComponents()
        parts.year = y; parts.month = m; parts.day = 1
        parts.hour = hour; parts.minute = minute; parts.second = second
        let first = calendar.date(from: parts) ?? Date()
        return calendar.date(byAdding: .day, value: day - 1, to: first) ?? first
    }

    static func parts(_ d: Date) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, weekday: Int) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: d)
        // weekday: 1 = Monday … 7 = Sunday, like Dart.
        let w = ((c.weekday ?? 1) + 5) % 7 + 1
        return (c.year ?? 2000, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, w)
    }

    static func year(_ d: Date) -> Int { parts(d).year }
    static func month(_ d: Date) -> Int { parts(d).month }
    static func day(_ d: Date) -> Int { parts(d).day }
    static func hour(_ d: Date) -> Int { parts(d).hour }

    static func dateOnly(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    static func monthStart(_ d: Date) -> Date { let p = parts(d); return date(p.year, p.month, 1) }
    static func daysInMonth(_ d: Date) -> Int { let p = parts(d); return day(date(p.year, p.month + 1, 0)) }

    static func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }
    static func sameMonth(_ a: Date, _ b: Date) -> Bool {
        let x = parts(a), y = parts(b); return x.year == y.year && x.month == y.month
    }

    /// Whole days from `a` to `b` (calendar days, both reduced to midnight).
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: dateOnly(a), to: dateOnly(b)).day ?? 0
    }
}

/// "2026-10-27": a calendar day with no time zone, for subscription dates.
func dayKey(_ d: Date) -> String {
    let p = Cal.parts(d)
    return String(format: "%04d-%02d-%02d", p.year, p.month, p.day)
}

func parseDayKey(_ value: Any?) throws -> Date {
    let parts = (value as? String)?.split(separator: "-").map { Int($0) } ?? []
    guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2], (1...12).contains(m), (1...31).contains(d) else {
        throw LedgerError(tr("记录含无效日期、金额或账户。"))
    }
    return Cal.date(y, m, d)
}

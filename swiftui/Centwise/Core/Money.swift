import Foundation

/// A ledger problem shown to the user (validation, import, parsing). `message` is already translated.
struct LedgerError: Error, CustomStringConvertible, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
    var errorDescription: String? { message }
}

/// Money is integer fen (cents), never a binary floating-point value.
enum Money {
    static let maximum: Int = 9_000_000_000_000

    /// The operators the in-app keypad may insert: '+ - × ÷' (plus ASCII '*' and '/' for typed input).
    static let operators: Set<String> = ["+", "-", "−", "×", "*", "÷", "/"]

    /// Symbol of the ledger's currency; the store keeps it in step with the ledger.
    nonisolated(unsafe) static var symbol = "¥"

    private static func isNumber(_ token: String) -> Bool {
        token.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil
    }

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentIsNumber = false
        for ch in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            let numeric = ch.isASCII && (ch.isNumber || ch == ".")
            if current.isEmpty {
                current = String(ch); currentIsNumber = numeric
            } else if numeric == currentIsNumber {
                current.append(ch)
            } else {
                result.append(current); current = String(ch); currentIsNumber = numeric
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Exact rational on Decimal integers (38 significant digits is far more than amounts need).
    private struct Ratio { var n: Decimal; var d: Decimal }

    private static func trunc(_ x: Decimal) -> Decimal {
        var value = x, result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }

    /// Integer quotient of two non-negative Decimal integers, exact (corrects division rounding).
    private static func intDiv(_ a: Decimal, _ b: Decimal) -> (Decimal, Decimal) {
        var q = trunc(a / b)
        var r = a - q * b
        while r < 0 { q -= 1; r += b }
        while r >= b { q += 1; r -= b }
        return (q, r)
    }

    /// Parses user input such as "12.34" or "-26.14", or a short calculation typed on the keypad,
    /// e.g. "12.5+8×2": × ÷ before + −, evaluated exactly and rounded half away from zero to fen.
    static func parse(_ text: String) throws -> Int {
        let tokens = tokens(text)
        let inputError = LedgerError(tr("请输入金额，最多保留两位小数，不要使用千位分隔符。"))
        if tokens.isEmpty { throw inputError }
        for token in tokens where !isNumber(token) {
            if token.count != 1 || !operators.contains(token) { throw inputError }
        }
        var at = 0
        func factor() throws -> Ratio {
            if at == 0 && tokens[0] == "-" {
                at += 1
                if at >= tokens.count { throw inputError }
                let value = try factor()
                return Ratio(n: -value.n, d: value.d)
            }
            let token = tokens[at]
            if !isNumber(token) { throw inputError }
            at += 1
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            let whole = String(parts[0])
            var fraction = parts.count > 1 ? String(parts[1]) : ""
            while fraction.count < 2 { fraction += "0" }
            return Ratio(n: Decimal(string: whole + fraction) ?? 0, d: 100)
        }
        func term() throws -> Ratio {
            var left = try factor()
            while at < tokens.count, ["×", "*", "÷", "/"].contains(tokens[at]) {
                let op = tokens[at]; at += 1
                if at >= tokens.count { throw inputError }
                let right = try factor()
                if op == "÷" || op == "/" {
                    if right.n == 0 { throw LedgerError(tr("算式里不能除以零。")) }
                    left = Ratio(n: left.n * right.d, d: left.d * right.n)
                } else {
                    left = Ratio(n: left.n * right.n, d: left.d * right.d)
                }
            }
            return left
        }
        var value = try term()
        while at < tokens.count {
            let op = tokens[at]; at += 1
            if op != "+" && op != "-" && op != "−" { throw inputError }
            if at >= tokens.count { throw inputError }
            let right = try term()
            value = op == "+"
                ? Ratio(n: value.n * right.d + right.n * value.d, d: value.d * right.d)
                : Ratio(n: value.n * right.d - right.n * value.d, d: value.d * right.d)
        }
        var (n, d) = (value.n, value.d)
        if d < 0 { n = -n; d = -d }
        let negative = n < 0
        let scaled = (negative ? -n : n) * 100
        let (q, r) = intDiv(scaled, d)
        let rounded = r * 2 >= d ? q + 1 : q
        if rounded > Decimal(maximum) { throw LedgerError(tr("金额超出范围，或含有超过两位小数的有效精度。")) }
        let cents = NSDecimalNumber(decimal: rounded).intValue
        return negative ? -cents : cents
    }

    /// SQLite REAL is read as text first; tolerate only representation noise below 1/10000 fen.
    static func legacy(_ text: String) throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw LedgerError(tr("旧账本含有无法识别的金额。"))
        }
        var scaled = value * 100
        var candidate = Decimal()
        NSDecimalRound(&candidate, &scaled, 0, .plain)
        var difference = scaled - candidate
        if difference < 0 { difference = -difference }
        if difference * 10000 > 1 { throw LedgerError(tr("金额超出范围，或含有超过两位小数的有效精度。")) }
        if candidate > Decimal(maximum) || candidate < -Decimal(maximum) {
            throw LedgerError(tr("金额超出范围，或含有超过两位小数的有效精度。"))
        }
        return NSDecimalNumber(decimal: candidate).intValue
    }

    /// "¥1,234.56" / "-¥1,234.56", or "1,234.56" without the symbol.
    static func text(_ cents: Int, symbol showSymbol: Bool = true) -> String {
        let negative = cents < 0
        let magnitude = cents.magnitude
        let whole = String(magnitude / 100)
        let fraction = String(format: "%02d", Int(magnitude % 100))
        return "\(negative ? "-" : "")\(showSymbol ? symbol : "")\(grouped(whole)).\(fraction)"
    }

    /// "1234567" → "1,234,567".
    static func grouped(_ whole: String) -> String {
        var out = ""
        let chars = Array(whole)
        for (i, c) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return out
    }

    /// Plain editable form without trailing zeros: 1230 → "12.3", -2614 → "-26.14", 0 → "0".
    static func input(_ cents: Int) -> String {
        let negative = cents < 0
        let magnitude = cents.magnitude
        let whole = magnitude / 100
        var fraction = String(format: "%02d", Int(magnitude % 100))
        while fraction.hasSuffix("0") { fraction.removeLast() }
        let body = fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
        return negative && magnitude != 0 ? "-\(body)" : body
    }

    /// Thousands separators inside a typed expression: "12345.6+800" → "12,345.6+800".
    static func groupedExpression(_ text: String) -> String {
        var out = ""
        var number = ""
        func flush() {
            guard !number.isEmpty else { return }
            if let dot = number.firstIndex(of: ".") {
                out += grouped(String(number[..<dot])) + number[dot...]
            } else {
                out += grouped(number)
            }
            number = ""
        }
        for ch in text {
            if ch.isASCII && (ch.isNumber || ch == ".") { number.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }
}

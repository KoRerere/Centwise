import SwiftUI

/// A tiny SVG renderer for icon markup on a 24×24 grid (Lucide icons and the settings tile glyphs):
/// path, circle, ellipse, rect, line, polyline, polygon and g, with fill / stroke attributes.
struct SVGGlyph {
    enum Paint: Equatable { case none, current, token(String), color(UInt32) }

    struct Item {
        var path: Path
        var fill: Paint
        var stroke: Paint
        var lineWidth: CGFloat?
        var cap: CGLineCap
        var join: CGLineJoin
        var opacity: Double
    }

    var items: [Item]

    nonisolated(unsafe) private static var cache: [String: SVGGlyph] = [:]

    /// Parses `markup`; elements default to Lucide's style (stroke = currentColor, no fill, round caps).
    static func parse(_ markup: String, defaultFill: Paint = .none, defaultStroke: Paint = .current) -> SVGGlyph {
        let key = "\(defaultFill)|\(defaultStroke)|\(markup)"
        if let hit = cache[key] { return hit }
        var items: [Item] = []
        var groupStack: [[String: String]] = []
        let pattern = try! NSRegularExpression(pattern: #"<(/?)(\w+)([^>]*?)(/?)>"#)
        let ns = markup as NSString
        for m in pattern.matches(in: markup, range: NSRange(location: 0, length: ns.length)) {
            let closing = ns.substring(with: m.range(at: 1)) == "/"
            let tag = ns.substring(with: m.range(at: 2))
            let attrs = attributes(ns.substring(with: m.range(at: 3)))
            let selfClosing = ns.substring(with: m.range(at: 4)) == "/"
            if tag == "g" {
                if closing { if !groupStack.isEmpty { groupStack.removeLast() } } else if !selfClosing { groupStack.append(attrs) }
                continue
            }
            if closing { continue }
            var a: [String: String] = [:]
            for g in groupStack { a.merge(g) { _, new in new } }
            a.merge(attrs) { _, new in new }
            guard let path = shape(tag, a) else { continue }
            func paint(_ v: String?, _ fallback: Paint) -> Paint {
                guard let v else { return fallback }
                if v == "none" { return .none }
                if v == "currentColor" { return .current }
                if v.hasPrefix("{") { return .token(v) }
                if v.hasPrefix("#"), let hex = UInt32(v.dropFirst(), radix: 16) { return .color(hex) }
                return fallback
            }
            let cap: CGLineCap = a["stroke-linecap"] == "butt" ? .butt : (a["stroke-linecap"] == "square" ? .square : .round)
            let join: CGLineJoin = a["stroke-linejoin"] == "miter" ? .miter : (a["stroke-linejoin"] == "bevel" ? .bevel : .round)
            items.append(Item(path: path, fill: paint(a["fill"], defaultFill), stroke: paint(a["stroke"], defaultStroke),
                              lineWidth: a["stroke-width"].flatMap { Double($0) }.map { CGFloat($0) }, cap: cap, join: join,
                              opacity: a["stroke-opacity"].flatMap { Double($0) } ?? 1))
        }
        let glyph = SVGGlyph(items: items)
        cache[key] = glyph
        return glyph
    }

    private static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let re = try! NSRegularExpression(pattern: #"([\w:-]+)\s*=\s*"([^"]*)""#)
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
        }
        return result
    }

    private static func num(_ a: [String: String], _ k: String) -> CGFloat { CGFloat(Double(a[k] ?? "") ?? 0) }

    private static func shape(_ tag: String, _ a: [String: String]) -> Path? {
        switch tag {
        case "path": return SVGPathParser.path(a["d"] ?? "")
        case "circle":
            let r = num(a, "r")
            return Path(ellipseIn: CGRect(x: num(a, "cx") - r, y: num(a, "cy") - r, width: 2 * r, height: 2 * r))
        case "ellipse":
            let rx = num(a, "rx"), ry = num(a, "ry")
            return Path(ellipseIn: CGRect(x: num(a, "cx") - rx, y: num(a, "cy") - ry, width: 2 * rx, height: 2 * ry))
        case "rect":
            let rect = CGRect(x: num(a, "x"), y: num(a, "y"), width: num(a, "width"), height: num(a, "height"))
            var rx = a["rx"] != nil ? num(a, "rx") : num(a, "ry")
            var ry = a["ry"] != nil ? num(a, "ry") : rx
            rx = min(rx, rect.width / 2); ry = min(ry, rect.height / 2)
            return rx > 0 ? Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: ry)) : Path(rect)
        case "line":
            var p = Path()
            p.move(to: CGPoint(x: num(a, "x1"), y: num(a, "y1")))
            p.addLine(to: CGPoint(x: num(a, "x2"), y: num(a, "y2")))
            return p
        case "polyline", "polygon":
            let values = SVGPathParser.numbers(a["points"] ?? "")
            var p = Path()
            var i = 0
            while i + 1 < values.count {
                let pt = CGPoint(x: values[i], y: values[i + 1])
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                i += 2
            }
            if tag == "polygon" { p.closeSubpath() }
            return p
        default: return nil
        }
    }
}

/// SVG path data → SwiftUI Path (all commands, relative and absolute, arcs included).
enum SVGPathParser {
    static func numbers(_ s: String) -> [CGFloat] {
        var result: [CGFloat] = []
        var scanner = Array(s.utf8)
        scanner.append(0)
        var i = 0
        while i < scanner.count - 1 {
            let c = scanner[i]
            if c == 45 || c == 43 || c == 46 || (c >= 48 && c <= 57) {
                var j = i
                if c == 45 || c == 43 { j += 1 }
                var seenDot = false, seenExp = false
                while j < scanner.count - 1 {
                    let d = scanner[j]
                    if d >= 48 && d <= 57 { j += 1 }
                    else if d == 46 && !seenDot && !seenExp { seenDot = true; j += 1 }
                    else if (d == 101 || d == 69) && !seenExp { seenExp = true; j += 1; if scanner[j] == 45 || scanner[j] == 43 { j += 1 } }
                    else { break }
                }
                if let v = Double(String(decoding: scanner[i..<j], as: UTF8.self)) { result.append(CGFloat(v)) }
                i = max(j, i + 1)
            } else { i += 1 }
        }
        return result
    }

    /// Arc flags may be written without separators ("a1 1 0 011 1"); read them one character at a time.
    private static func tokens(_ d: String) -> [(Character, [CGFloat])] {
        var out: [(Character, [CGFloat])] = []
        var command: Character?
        var buffer = ""
        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                if let c = command { out.append((c, parseArgs(c, buffer))) }
                command = ch; buffer = ""
            } else { buffer.append(ch) }
        }
        if let c = command { out.append((c, parseArgs(c, buffer))) }
        return out
    }

    private static func parseArgs(_ command: Character, _ text: String) -> [CGFloat] {
        guard command == "a" || command == "A" else { return numbers(text) }
        // rx ry rotation large sweep x y — flags are single digits that may run together.
        var values: [CGFloat] = []
        var chars = Array(text)
        var index = 0
        var slot = 0
        while index < chars.count {
            let c = chars[index]
            if c == " " || c == "," || c == "\n" || c == "\t" { index += 1; continue }
            let position = slot % 7
            if position == 3 || position == 4 {
                values.append(c == "1" ? 1 : 0); index += 1; slot += 1; continue
            }
            var j = index
            var token = ""
            if chars[j] == "-" || chars[j] == "+" { token.append(chars[j]); j += 1 }
            var seenDot = false, seenExp = false
            while j < chars.count {
                let d = chars[j]
                if d.isNumber { token.append(d); j += 1 }
                else if d == "." && !seenDot && !seenExp { seenDot = true; token.append(d); j += 1 }
                else if (d == "e" || d == "E") && !seenExp { seenExp = true; token.append(d); j += 1
                    if j < chars.count, chars[j] == "-" || chars[j] == "+" { token.append(chars[j]); j += 1 } }
                else { break }
            }
            if j == index { index += 1; continue }
            values.append(CGFloat(Double(token) ?? 0)); index = j; slot += 1
        }
        chars.removeAll()
        return values
    }

    static func path(_ d: String) -> Path {
        var p = Path()
        var current = CGPoint.zero, start = CGPoint.zero
        var lastControl: CGPoint?, lastQuad: CGPoint?
        var previous: Character = " "
        for (command, args) in tokens(d) {
            let rel = command.isLowercase
            let c = Character(command.uppercased())
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y) }
            var i = 0
            func take(_ n: Int) -> [CGFloat]? {
                guard i + n <= args.count else { return nil }
                defer { i += n }
                return Array(args[i..<(i + n)])
            }
            switch c {
            case "M":
                var first = true
                while let v = take(2) {
                    let point = pt(v[0], v[1])
                    if first { p.move(to: point); start = point; first = false } else { p.addLine(to: point) }
                    current = point
                }
                lastControl = nil; lastQuad = nil
            case "L":
                while let v = take(2) { current = pt(v[0], v[1]); p.addLine(to: current) }
                lastControl = nil; lastQuad = nil
            case "H":
                while let v = take(1) { current = CGPoint(x: rel ? current.x + v[0] : v[0], y: current.y); p.addLine(to: current) }
                lastControl = nil; lastQuad = nil
            case "V":
                while let v = take(1) { current = CGPoint(x: current.x, y: rel ? current.y + v[0] : v[0]); p.addLine(to: current) }
                lastControl = nil; lastQuad = nil
            case "C":
                while let v = take(6) {
                    let c1 = pt(v[0], v[1]), c2 = pt(v[2], v[3]), end = pt(v[4], v[5])
                    p.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2; current = end
                }
                lastQuad = nil
            case "S":
                while let v = take(4) {
                    let c1 = (previous == "C" || previous == "S") && lastControl != nil
                        ? CGPoint(x: 2 * current.x - lastControl!.x, y: 2 * current.y - lastControl!.y) : current
                    let c2 = pt(v[0], v[1]), end = pt(v[2], v[3])
                    p.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2; current = end; previous = "S"
                }
                lastQuad = nil
            case "Q":
                while let v = take(4) {
                    let c1 = pt(v[0], v[1]), end = pt(v[2], v[3])
                    p.addQuadCurve(to: end, control: c1)
                    lastQuad = c1; current = end
                }
                lastControl = nil
            case "T":
                while let v = take(2) {
                    let c1 = (previous == "Q" || previous == "T") && lastQuad != nil
                        ? CGPoint(x: 2 * current.x - lastQuad!.x, y: 2 * current.y - lastQuad!.y) : current
                    let end = pt(v[0], v[1])
                    p.addQuadCurve(to: end, control: c1)
                    lastQuad = c1; current = end; previous = "T"
                }
                lastControl = nil
            case "A":
                while let v = take(7) {
                    let end = pt(v[5], v[6])
                    arc(&p, from: current, to: end, rx: v[0], ry: v[1], rotation: v[2], large: v[3] != 0, sweep: v[4] != 0)
                    current = end
                }
                lastControl = nil; lastQuad = nil
            case "Z":
                p.closeSubpath(); current = start
                lastControl = nil; lastQuad = nil
            default: break
            }
            previous = c
        }
        return p
    }

    /// SVG endpoint arc → center parameterisation, drawn as a transformed unit-circle arc.
    private static func arc(_ p: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { p.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        // Approximate with cubic segments of at most 90°.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)
        var a1 = theta1
        func point(_ a: CGFloat) -> CGPoint {
            let x = rx * cos(a), y = ry * sin(a)
            return CGPoint(x: cx + cosP * x - sinP * y, y: cy + sinP * x + cosP * y)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            let x = -rx * sin(a), y = ry * cos(a)
            return CGPoint(x: cosP * x - sinP * y, y: sinP * x + cosP * y)
        }
        for _ in 0..<segments {
            let a2 = a1 + step
            let s = point(a1), e = point(a2), d1 = derivative(a1), d2 = derivative(a2)
            p.addCurve(to: e, control1: CGPoint(x: s.x + t * d1.x, y: s.y + t * d1.y), control2: CGPoint(x: e.x - t * d2.x, y: e.y - t * d2.y))
            a1 = a2
        }
    }
}

/// Draws an SVGGlyph scaled from the 24×24 grid to the view's frame.
struct SVGGlyphView: View {
    let glyph: SVGGlyph
    var color: Color
    var strokeWidth: CGFloat = 2
    var tokens: [String: Color] = [:]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.translateBy(x: (size.width - 24 * scale) / 2, y: (size.height - 24 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            for item in glyph.items {
                if let fill = resolve(item.fill) {
                    context.fill(item.path, with: .color(fill))
                }
                if let stroke = resolve(item.stroke) {
                    context.stroke(item.path, with: .color(stroke.opacity(item.opacity)),
                                   style: StrokeStyle(lineWidth: item.lineWidth ?? strokeWidth, lineCap: item.cap, lineJoin: item.join))
                }
            }
        }
    }

    private func resolve(_ paint: SVGGlyph.Paint) -> Color? {
        switch paint {
        case .none: nil
        case .current: color
        case .token(let t): tokens[t] ?? color
        case .color(let hex): Color(hex: hex)
        }
    }
}

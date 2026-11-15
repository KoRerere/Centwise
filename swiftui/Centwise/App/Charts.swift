import SwiftUI

private let expenseBar = Color(lightHex: 0xEAA340, darkHex: 0xF0AE4E)
private let incomeBar = Color(lightHex: 0x478BF4, darkHex: 0x5B9BFF)

/// Monotone cubic interpolation (Fritsch–Carlson): smooth, never overshoots between points.
func monotonePath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    let n = points.count
    if n == 1 { return path }
    var slopes = [CGFloat](repeating: 0, count: n - 1)
    for i in 0..<(n - 1) {
        let dx = points[i + 1].x - points[i].x
        slopes[i] = dx == 0 ? 0 : (points[i + 1].y - points[i].y) / dx
    }
    var tangents = [CGFloat](repeating: 0, count: n)
    tangents[0] = slopes[0]
    tangents[n - 1] = slopes[n - 2]
    if n > 2 {
        for i in 1..<(n - 1) { tangents[i] = slopes[i - 1] * slopes[i] <= 0 ? 0 : (slopes[i - 1] + slopes[i]) / 2 }
    }
    for i in 0..<(n - 1) {
        if slopes[i] == 0 { tangents[i] = 0; tangents[i + 1] = 0; continue }
        let a = tangents[i] / slopes[i], b = tangents[i + 1] / slopes[i]
        let h = a * a + b * b
        if h > 9 {
            let t = 3 / sqrt(h)
            tangents[i] = t * a * slopes[i]
            tangents[i + 1] = t * b * slopes[i]
        }
    }
    for i in 0..<(n - 1) {
        let p0 = points[i], p1 = points[i + 1]
        let dx = (p1.x - p0.x) / 3
        path.addCurve(to: p1, control1: CGPoint(x: p0.x + dx, y: p0.y + tangents[i] * dx), control2: CGPoint(x: p1.x - dx, y: p1.y - tangents[i + 1] * dx))
    }
    return path
}

/// Running total this period (solid) against the previous period (dashed).
struct CumulativeChart: View {
    let current: [Double]
    let previous: [Double]
    let domainMax: Int
    var ticks: [String] = []
    var height: CGFloat = 112

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let width = size.width
                let all = current + previous
                let maxValue = (all + [1]).max()!, minValue = (all + [0]).min()!
                let span = maxValue - minValue <= 0 ? 1 : maxValue - minValue
                func y(_ v: Double) -> CGFloat { height - 4 - CGFloat((v - minValue) / span) * (height - 12) }
                func at(_ i: Int, _ v: Double) -> CGPoint { CGPoint(x: domainMax <= 1 ? 0 : CGFloat(i) / CGFloat(domainMax - 1) * width, y: y(v)) }
                var base = Path()
                base.move(to: CGPoint(x: 0, y: y(0))); base.addLine(to: CGPoint(x: width, y: y(0)))
                context.stroke(base, with: .color(.cwTrack), lineWidth: 1)
                if previous.count > 1 {
                    context.stroke(monotonePath(previous.enumerated().map { at($0.offset, $0.element) }), with: .color(Color.cwMuted.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                }
                let points = current.enumerated().map { at($0.offset, $0.element) }
                if points.count > 1 {
                    context.stroke(monotonePath(points), with: .color(.cwBrand), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let last = points.last {
                    context.fill(Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8)), with: .color(.cwBrand))
                }
            }
            .frame(height: height)
            if !ticks.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(ticks.enumerated()), id: \.offset) { i, tick in
                        Text(tick).cw(11, color: .cwMuted)
                            .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : (i == ticks.count - 1 ? .trailing : .center))
                    }
                }
            }
        }
    }
}

struct DashLine: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY)); return p }
}

/// 12 monthly bars with a dashed monthly-average line and its label.
struct MonthBarsChart: View {
    let values: [Int]
    let labels: [String]
    let average: Int
    let highlight: Int
    var height: CGFloat = 150

    var body: some View {
        let maxValue = Double(max((values + [average]).max() ?? 1, 1))
        let labelHeight: CGFloat = 18
        let plot = height - labelHeight
        let averageY = plot - CGFloat(Double(average) / maxValue) * (plot - 12)
        ZStack(alignment: .topLeading) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(values.indices, id: \.self) { i in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        GeometryReader { geo in
                            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                .fill(i == highlight ? Color.cwBrand : Color.cwInk.opacity(values[i] > average ? 0.32 : 0.14))
                                .frame(width: geo.size.width * 0.62)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(height: max(0, CGFloat(Double(values[i]) / maxValue) * (plot - 12)))
                        Text(labels[i]).cw(10, .semibold, color: .cwMuted).frame(height: labelHeight)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            DashLine().stroke(Color.cwInk.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1).offset(y: averageY)
            HStack(spacing: 0) {
                Text(tr("月均 ")).cw(10, .bold, color: .cwCard)
                AmountText(cents: average, size: 10, weight: .bold, sign: "", color: .cwCard)
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.cwInk))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(y: max(0, averageY - 20))
        }
        .frame(height: height)
    }
}

/// Category share ring with small gaps between slices.
struct DonutChart: View {
    let slices: [(Double, Color)]
    var size: CGFloat = 92
    var thickness: CGFloat = 13

    var body: some View {
        Canvas { context, s in
            let radius = s.width / 2 - thickness / 2
            let center = CGPoint(x: s.width / 2, y: s.height / 2)
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .zero, endAngle: .radians(2 * .pi), clockwise: false)
            context.stroke(ring, with: .color(.cwTrack), lineWidth: thickness)
            let total = slices.reduce(0) { $0 + $1.0 }
            guard total > 0 else { return }
            let gap = 0.035
            var start = -Double.pi / 2
            for (value, color) in slices {
                let sweep = value / total * 2 * .pi
                if sweep > gap * 1.5 {
                    var arc = Path()
                    arc.addArc(center: center, radius: radius, startAngle: .radians(start + gap / 2), endAngle: .radians(start + sweep - gap / 2), clockwise: false)
                    context.stroke(arc, with: .color(color), lineWidth: thickness)
                }
                start += sweep
            }
        }
        .frame(width: size, height: size)
    }
}

/// Six months of income / expense bars. Tap a month to see its figures in the header.
struct TrendChart: View {
    let labels: [String]
    var titles: [String]?
    let income: [Int]
    let expense: [Int]
    var height: CGFloat = 190
    @State private var selected: Int?

    var body: some View {
        let count = labels.count
        let maxValue = Double(max((income + expense).max() ?? 1, 1))
        let labelHeight: CGFloat = 20
        let plot = height - labelHeight
        let usable = plot - 4
        let barHeight: (Int) -> CGFloat = { v in max(0, CGFloat(Double(v) / maxValue) * usable) }
        VStack(alignment: .leading, spacing: 8) {
            header.frame(height: 40)
            GeometryReader { geo in
                let column = geo.size.width / CGFloat(max(count, 1))
                ZStack(alignment: .topLeading) {
                    if let selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.cwTrack.opacity(0.5))
                            .frame(width: column - 8, height: plot)
                            .offset(x: column * CGFloat(selected) + 4)
                    }
                    ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                        DashLine().stroke(Color.cwTrack, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
                            .offset(y: plot - CGFloat(f) * usable)
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<count, id: \.self) { i in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                HStack(alignment: .bottom, spacing: 4) {
                                    UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(incomeBar).frame(width: 20, height: barHeight(income[i]))
                                    UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6).fill(expenseBar).frame(width: 20, height: barHeight(expense[i]))
                                }
                                Text(labels[i]).cw(12, selected == i ? .semibold : .regular, color: selected == i ? .cwInk : .cwMuted).frame(height: labelHeight)
                            }
                            .frame(maxWidth: .infinity)
                            .opacity(selected == nil || selected == i ? 1 : 0.35)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let index = min(max(Int(location.x / column), 0), count - 1)
                    Haptics.selection()
                    withAnimation(IOSMotion.snappy) { selected = selected == index ? nil : index }
                }
            }
            .frame(height: height)
        }
    }

    @ViewBuilder private var header: some View {
        ZStack(alignment: .leading) {
            if let selected, selected < labels.count {
                VStack(alignment: .leading, spacing: 2) {
                    Text((titles ?? labels)[selected]).cw(12, .semibold, color: .cwMuted)
                    HStack(spacing: 12) {
                        figure(tr("收入"), incomeBar, income[selected])
                        figure(tr("支出"), expenseBar, expense[selected])
                        figure(tr("结余"), nil, income[selected] - expense[selected])
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                }
                .id(selected)
                .transition(.opacity.combined(with: .offset(y: 6)))
            } else {
                HStack(spacing: 14) {
                    legend(tr("收入"), incomeBar)
                    legend(tr("支出"), expenseBar)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).cw(12, .semibold, color: .cwMuted)
        }
    }

    private func figure(_ label: String, _ dot: Color?, _ cents: Int) -> some View {
        HStack(spacing: 4) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7).padding(.trailing, 1) }
            Text(label).cw(12, color: .cwMuted)
            AmountText(cents: cents, size: 14, weight: .semibold).fixedSize()
        }
    }
}

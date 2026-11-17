import SwiftUI

/// Every emoji on one flat square grid, which the sphere shows a round window of.
private struct EmojiGrid {
    let emojis: [String]
    let columns: Int
    let index: [String: Int]

    var rows: Int { (emojis.count + columns - 1) / columns }

    func point(_ i: Int) -> CGPoint {
        CGPoint(x: CGFloat(i % columns) * Sphere.pitch, y: CGFloat(i / columns) * Sphere.pitch)
    }

    /// The grid repeats in every direction, so the ball never runs out. The few cells left over in the
    /// last row borrow emoji from the middle of the list (not the start, which is the row right below).
    func emojiIndex(row: Int, col: Int) -> Int {
        let r = ((row % rows) + rows) % rows, c = ((col % columns) + columns) % columns
        let i = r * columns + c
        return i < emojis.count ? i : (emojis.count / 2 + i - emojis.count) % emojis.count
    }

    /// The copy of cell `i` closest to `p`.
    func point(_ i: Int, nearest p: CGPoint) -> CGPoint {
        let base = point(i)
        let w = CGFloat(columns) * Sphere.pitch, h = CGFloat(rows) * Sphere.pitch
        return CGPoint(x: base.x + w * ((p.x - base.x) / w).rounded(), y: base.y + h * ((p.y - base.y) / h).rounded())
    }

    private static var cache: [[String]: EmojiGrid] = [:]

    /// `first` (the curated icons) lead the grid, then every other emoji in the system picker's order.
    static func make(first: [String]) -> EmojiGrid {
        if let hit = cache[first] { return hit }
        var seen = Set<String>()
        let all = (first + emojiGroups.flatMap { $0.emojis.map(\.0) }).filter { seen.insert($0).inserted }
        let grid = EmojiGrid(
            emojis: all,
            columns: max(1, Int(Double(all.count).squareRoot().rounded(.up))),
            index: Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1, $0) })
        )
        cache[first] = grid
        return grid
    }
}

/// Sizes at the sphere's natural radius; a smaller sphere scales all of them down together.
private enum Sphere {
    static let radius: CGFloat = 180
    /// Distance between neighbouring emoji on the flat grid.
    static let pitch: CGFloat = 50
    static let fontSize: CGFloat = 29
    /// Flat-grid distance from the middle of the sphere to its rim (a quarter of the way round).
    static let reach = CGFloat.pi / 2 * radius

    static let pillThickness: CGFloat = 48
    /// From the sphere's surface to the pill's centre line.
    static let pillOffset: CGFloat = 32
    /// Where the pill is centred, measured clockwise from the right (270° = straight above the ball).
    static let pillCentre: CGFloat = 270 * .pi / 180
    /// How far either side of `pillCentre` a tap still counts as hitting the pill.
    static let pillHitSpan: CGFloat = 0.75
    static let focusBlue = Color(red: 0.30, green: 0.56, blue: 0.96)
}

/// Category icon picker: all emoji wrapped over a ball. Drag to roll it, tap an emoji to pick it. The
/// search pill bends around the ball's top-left; while searching, matches stay lit where they sit, the
/// rest go dark, and the keyboard's "next" key rolls from match to match.
struct SphereIconPicker: View {
    let selected: String
    let defaults: [String]
    let onSelected: (String) -> Void

    private let grid: EmojiGrid
    @State private var pan: CGPoint
    @State private var dragStart: CGPoint?
    @State private var selection: String
    @State private var query = ""
    @State private var matches: [Int] = []
    @State private var current = 0
    @State private var shown = false
    @FocusState private var searching: Bool

    init(selected: String, defaults: [String], onSelected: @escaping (String) -> Void) {
        self.selected = selected
        self.defaults = defaults
        self.onSelected = onSelected
        let grid = EmojiGrid.make(first: defaults)
        self.grid = grid
        _selection = State(initialValue: selected)
        _pan = State(initialValue: grid.point(grid.index[selected] ?? 0))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        GeometryReader { geo in
            let layout = layout(in: geo.size)
            SphereCanvas(
                pan: pan,
                dim: trimmedQuery.isEmpty ? 0 : 1,
                grid: grid,
                radius: layout.radius,
                center: layout.center,
                selected: grid.index[selection],
                matches: Set(matches),
                query: trimmedQuery,
                placeholder: tr("搜索表情"),
                counter: matches.isEmpty ? "0" : "\(current + 1) / \(matches.count)",
                focused: searching
            )
            .animation(.easeOut(duration: 0.25), value: trimmedQuery.isEmpty)
            .scaleEffect(shown ? 1 : 0.3, anchor: UnitPoint(x: layout.center.x / max(geo.size.width, 1), y: layout.center.y / max(geo.size.height, 1)))
            .opacity(shown ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { tap(at: $0, layout: layout) }
            .gesture(dragGesture(scale: layout.radius / Sphere.radius))
            .background(alignment: .topLeading) { searchField }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { shown = true }
            // Launch argument for screenshots during development: -CWEmojiQuery.
            if let q = UserDefaults.standard.string(forKey: "CWEmojiQuery") { query = q }
        }
        .onChange(of: query) { runSearch() }
    }

    /// The ball is as big as fits, leaving room above and to the left for the pill.
    private func layout(in size: CGSize) -> (radius: CGFloat, center: CGPoint) {
        let top = Sphere.pillOffset + Sphere.pillThickness / 2 + 4
        // The pill may reach a little into the sheet's side margin.
        let byWidth = (size.width / 2 + 14) / 0.92 - Sphere.pillThickness / 2 - Sphere.pillOffset
        let byHeight = (size.height - top - 4) / 2
        let radius = max(40, min(Sphere.radius, byWidth, byHeight))
        let y = min(max(top + radius, size.height / 2), max(top + radius, size.height - radius - 4))
        return (radius, CGPoint(x: size.width / 2, y: y))
    }

    /// Takes the typing; the pill on the ball draws what it holds.
    private var searchField: some View {
        TextField("", text: $query)
            .focused($searching)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit {
                step()
                searching = true
            }
            .foregroundStyle(.clear)
            .tint(.clear)
            .frame(width: 2, height: 2)
            .clipped()
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityLabel(tr("搜索表情"))
    }

    // MARK: - Interaction

    private func dragGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? pan
                if dragStart == nil { dragStart = start; searching = false }
                pan = CGPoint(x: start.x - value.translation.width / scale, y: start.y - value.translation.height / scale)
            }
            .onEnded { value in
                dragStart = nil
                // Keep rolling the way it was thrown, slowing to a stop.
                let throwX = (value.predictedEndTranslation.width - value.translation.width) / scale
                let throwY = (value.predictedEndTranslation.height - value.translation.height) / scale
                withAnimation(.spring(duration: 0.9, bounce: 0)) {
                    pan = CGPoint(x: pan.x - throwX, y: pan.y - throwY)
                }
            }
    }

    private func tap(at location: CGPoint, layout: (radius: CGFloat, center: CGPoint)) {
        let dx = location.x - layout.center.x, dy = location.y - layout.center.y
        let r = hypot(dx, dy)
        if r < layout.radius * 0.97 {
            // Undo the projection: how far round the ball the tap is, then which grid cell is there.
            let theta = asin(r / layout.radius)
            let k = r > 0.001 ? theta * Sphere.radius / r : 0
            let col = Int(((pan.x + dx * k) / Sphere.pitch).rounded()), row = Int(((pan.y + dy * k) / Sphere.pitch).rounded())
            let i = grid.emojiIndex(row: row, col: col)
            if let m = matches.firstIndex(of: i) { current = m }
            pick(i)
            return
        }
        // The band the pill lives in, centred above the ball.
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let band = abs(r - layout.radius - Sphere.pillOffset) < Sphere.pillThickness / 2 + 8
        if band && abs(angle - Sphere.pillCentre) < Sphere.pillHitSpan {
            if searching { step() } else { searching = true }
        }
    }

    private func pick(_ i: Int) {
        let emoji = grid.emojis[i]
        if emoji != selection { Haptics.selection() }
        selection = emoji
        withAnimation(.spring(duration: 0.5, bounce: 0.12)) { pan = grid.point(i, nearest: pan) }
        if emoji != selected { onSelected(emoji) }
    }

    private func runSearch() {
        let q = trimmedQuery
        matches = q.isEmpty ? [] : HoneycombIconPicker.search(q, limit: .max).compactMap { grid.index[$0] }
        current = 0
        if let first = matches.first { pick(first) }
    }

    /// On to the next match, round to the first again after the last.
    private func step() {
        guard !matches.isEmpty else { return }
        current = (current + 1) % matches.count
        pick(matches[current])
    }
}

/// Draws the ball and its pill. `pan` (the grid point under the middle of the ball) and `dim` animate, so
/// a roll follows the ball's curve frame by frame.
private struct SphereCanvas: View, Animatable {
    var pan: CGPoint
    var dim: CGFloat
    let grid: EmojiGrid
    let radius: CGFloat
    let center: CGPoint
    let selected: Int?
    let matches: Set<Int>
    let query: String
    let placeholder: String
    let counter: String
    let focused: Bool

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(pan.x, pan.y), dim) }
        set { pan = CGPoint(x: newValue.first.first, y: newValue.first.second); dim = newValue.second }
    }

    /// A canvas only paints inside its frame, and the pill reaches into the sheet's side margin, so the
    /// canvas overhangs the picker's frame by this much on every side.
    private static let bleed: CGFloat = 24

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: Self.bleed, y: Self.bleed)
            drawEmoji(ctx)
            drawPill(ctx)
        }
        .padding(-Self.bleed)
    }

    private func drawEmoji(_ ctx: GraphicsContext) {
        let scale = radius / Sphere.radius
        let pitch = Sphere.pitch
        let c0 = Int(((pan.x - Sphere.reach) / pitch).rounded(.down)), c1 = Int(((pan.x + Sphere.reach) / pitch).rounded(.up))
        let r0 = Int(((pan.y - Sphere.reach) / pitch).rounded(.down)), r1 = Int(((pan.y + Sphere.reach) / pitch).rounded(.up))
        let tile = Path(roundedRect: CGRect(x: -21, y: -21, width: 42, height: 42), cornerRadius: 12, style: .continuous)

        for row in r0...r1 {
            for col in c0...c1 {
                let i = grid.emojiIndex(row: row, col: col)
                // The cell sits `d` along the ball's surface from its middle, at angle `theta` round it.
                let qx = CGFloat(col) * pitch - pan.x, qy = CGFloat(row) * pitch - pan.y
                let d = hypot(qx, qy)
                let theta = d / Sphere.radius
                guard theta < .pi / 2 - 0.04 else { continue }
                // Seen from the front: pulled in toward the middle, and squashed along that direction.
                let across = d > 0.001 ? sin(theta) / theta : 1
                let along = cos(theta)
                let direction = Angle.radians(atan2(qy, qx))

                var g = ctx
                g.translateBy(x: center.x + qx * across * scale, y: center.y + qy * across * scale)
                g.rotate(by: direction)
                g.scaleBy(x: along * scale, y: across * scale)
                g.rotate(by: -direction)

                let rim = min(1, pow(along, 0.7) * 1.25)
                if i == selected {
                    g.opacity = rim
                    g.fill(tile, with: .color(.cwTrack))
                    if dim > 0 {
                        g.opacity = rim * dim
                        g.stroke(tile, with: .color(Sphere.focusBlue), lineWidth: 2.5)
                    }
                }
                g.opacity = rim * (matches.contains(i) ? 1 : 1 - 0.86 * dim)
                g.draw(g.resolve(Text(grid.emojis[i]).font(.emoji(size: Sphere.fontSize))), at: .zero)
            }
        }
    }

    private func drawPill(_ ctx: GraphicsContext) {
        func glyphs(_ text: String, _ font: Font, _ color: Color) -> [(GraphicsContext.ResolvedText, CGFloat)] {
            text.map { ch in
                let resolved = ctx.resolve(Text(String(ch)).font(font).foregroundStyle(color))
                return (resolved, resolved.measure(in: CGSize(width: 400, height: 100)).width)
            }
        }
        let big = CGSize(width: 400, height: 100)
        let icon = ctx.resolve(Text(Image(systemName: "magnifyingglass")).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.cwMuted))

        // What sits along the pill, left to right: a width, and what to draw there (nil = a gap).
        var items: [(GraphicsContext.ResolvedText?, CGFloat)] = [(icon, icon.measure(in: big).width), (nil, 5)]
        var caretAt: Int?
        if query.isEmpty {
            if focused { caretAt = items.count; items.append((nil, 3)) }
            items += glyphs(placeholder, .cw(20, .medium), .cwMuted).map { ($0.0, $0.1) }
        } else {
            items += glyphs(String(query.suffix(12)), .cw(20, .bold), .cwInk).map { ($0.0, $0.1) }
            if focused { caretAt = items.count; items.append((nil, 3)) }
            items.append((nil, 6))
            items += glyphs(counter, .cw(16, .medium), .cwMuted).map { ($0.0, $0.1) }
        }

        let r = radius + Sphere.pillOffset
        let thickness = Sphere.pillThickness
        let padding: CGFloat = 18
        let length = items.reduce(padding * 2) { $0 + $1.1 }
        // Centred on the top of the ball, so it grows evenly both ways as the query gets longer.
        let pillStart = Sphere.pillCentre - length / 2 / r

        var line = Path()
        line.addArc(center: center, radius: r,
                    startAngle: .radians(pillStart + thickness / 2 / r),
                    endAngle: .radians(pillStart + (length - thickness / 2) / r),
                    clockwise: false)
        let body = line.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round))
        ctx.fill(body, with: .color(.cwTrack))
        if focused { ctx.stroke(body, with: .color(Sphere.focusBlue), lineWidth: 2) }

        var along = padding
        for (n, item) in items.enumerated() {
            let angle = pillStart + (along + item.1 / 2) / r
            along += item.1
            var g = ctx
            g.translateBy(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            g.rotate(by: .radians(angle + .pi / 2))
            if let text = item.0 {
                g.draw(text, at: .zero)
            } else if n == caretAt {
                g.fill(Path(roundedRect: CGRect(x: -1, y: -12, width: 2, height: 24), cornerRadius: 1), with: .color(Sphere.focusBlue))
            }
        }
    }
}

import SwiftUI

/// A draggable honeycomb of emoji bubbles, like the Apple Watch home screen: bubbles near the middle are
/// full size, bubbles toward the edge shrink, pull inward and fade. Drag to pan; on release the grid
/// glides to the bubble nearest the centre, which becomes the selection and gets a ring. Tap a bubble to
/// bring it to the centre. Changing the order of `emojis` (e.g. shuffling) flies each bubble to its new cell.
struct EmojiHoneycomb: View {
    /// Cell order: index 0 is the middle cell, then ring by ring outward.
    let emojis: [String]
    @Binding var selection: String?
    var cellSize: CGFloat = 54
    var gap: CGFloat = 6

    @State private var pan: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var centered: Int?

    private var pitch: CGFloat { cellSize + gap }

    var body: some View {
        GeometryReader { geo in
            let cells = HexCell.spiral(count: emojis.count)
            let radii = CGSize(width: geo.size.width / 2, height: geo.size.height / 2)
            ZStack {
                ForEach(Array(emojis.enumerated()), id: \.element) { i, emoji in
                    let base = cells[i].point(pitch: pitch)
                    Text(emoji)
                        .font(.emoji(size: cellSize * 0.5))
                        .frame(width: cellSize, height: cellSize)
                        .background(Circle().fill(Color.cwTrack))
                        .overlay {
                            Circle()
                                .strokeBorder(Color.cwMuted, lineWidth: 2.5)
                                .padding(-5.5)
                                .opacity(dragStart == nil && selection == emoji ? 1 : 0)
                                .animation(.easeOut(duration: 0.2), value: dragStart == nil && selection == emoji)
                        }
                        .contentShape(Circle())
                        .modifier(FisheyeEffect(pan: pan, base: base, radii: radii, cellSize: cellSize))
                        .onTapGesture { focus(on: i, cells: cells) }
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(cells: cells))
            .onAppear { restoreSelection(cells: cells) }
            .onChange(of: emojis) { old, now in
                guard !now.isEmpty else { selection = nil; centered = nil; return }
                if Set(old) == Set(now), let c = centered, c < now.count {
                    // Shuffled: the cell under the centre stays put, its new occupant becomes the selection.
                    selection = now[c]
                } else {
                    // New set (e.g. search results): glide back to the middle, where the best match sits.
                    settle(on: 0, cells: HexCell.spiral(count: now.count), animation: .spring(duration: 0.5, bounce: 0.12), emojis: now)
                }
            }
        }
    }

    // MARK: - Interaction

    private func dragGesture(cells: [HexCell]) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = dragStart ?? pan
                if dragStart == nil { dragStart = start }
                let raw = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                pan = rubberBand(raw, cells: cells)
                let nearest = nearestCell(to: pan, cells: cells)
                if nearest != centered { centered = nearest; Haptics.selection() }
            }
            .onEnded { value in
                let start = dragStart ?? pan
                let projected = CGSize(
                    width: start.width + value.predictedEndTranslation.width,
                    height: start.height + value.predictedEndTranslation.height
                )
                dragStart = nil
                let target = nearestCell(to: projected, cells: cells)
                settle(on: target, cells: cells, animation: .spring(duration: 0.55, bounce: 0.18))
            }
    }

    private func focus(on index: Int, cells: [HexCell]) {
        guard dragStart == nil else { return }
        if index != centered { Haptics.selection() }
        settle(on: index, cells: cells, animation: .spring(duration: 0.5, bounce: 0.15))
    }

    private func settle(on index: Int, cells: [HexCell], animation: Animation, emojis: [String]? = nil) {
        let emojis = emojis ?? self.emojis
        guard index < emojis.count, index < cells.count else { return }
        let p = cells[index].point(pitch: pitch)
        centered = index
        withAnimation(animation) {
            pan = CGSize(width: -p.x, height: -p.y)
        }
        selection = emojis[index]
    }

    private func restoreSelection(cells: [HexCell]) {
        guard !emojis.isEmpty else { return }
        let index = selection.flatMap { emojis.firstIndex(of: $0) } ?? 0
        let p = cells[index].point(pitch: pitch)
        pan = CGSize(width: -p.x, height: -p.y)
        centered = index
        selection = emojis[index]
    }

    /// Index of the cell that sits closest to the viewport centre when the grid is panned by `offset`.
    private func nearestCell(to offset: CGSize, cells: [HexCell]) -> Int {
        var best = 0, bestDistance = CGFloat.infinity
        for (i, cell) in cells.enumerated() {
            let p = cell.point(pitch: pitch)
            let d = hypot(p.x + offset.width, p.y + offset.height)
            if d < bestDistance { best = i; bestDistance = d }
        }
        return best
    }

    /// Past the outermost ring the pan resists, like a scroll view at its edge.
    private func rubberBand(_ offset: CGSize, cells: [HexCell]) -> CGSize {
        let limit = CGFloat(cells.last?.ring ?? 0) * pitch * 0.9
        let length = hypot(offset.width, offset.height)
        guard length > limit, length > 0 else { return offset }
        let excess = length - limit
        let damped = limit + excess * 120 / (excess + 120) * 0.55
        let k = damped / length
        return CGSize(width: offset.width * k, height: offset.height * k)
    }
}

/// Places one bubble: its distance from the centre (on an ellipse fitted to the view) sets how much it
/// shrinks, pulls inward and fades. Both the pan and the bubble's own cell animate, so a spring follows
/// the fisheye curve frame by frame instead of interpolating straight to the end state.
private struct FisheyeEffect: ViewModifier, Animatable {
    var pan: CGSize
    var base: CGPoint
    let radii: CGSize
    let cellSize: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(pan.width, pan.height), AnimatablePair(base.x, base.y)) }
        set {
            pan = CGSize(width: newValue.first.first, height: newValue.first.second)
            base = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func body(content: Content) -> some View {
        let x = base.x + pan.width, y = base.y + pan.height
        // Leave room for half a bubble so edge bubbles shrink before they hit the frame.
        let rx = max(radii.width - cellSize * 0.2, 1), ry = max(radii.height - cellSize * 0.2, 1)
        let e = sqrt((x / rx) * (x / rx) + (y / ry) * (y / ry))

        let shrink = smoothstep(0.12, 1.3, e)
        let scale = max(0, 1.1 - 0.72 * shrink)
        let pull = 1 - 0.2 * smoothstep(0.5, 1.6, e)
        let fade = (1 - 0.4 * smoothstep(0.55, 1.05, e)) * (1 - smoothstep(0.95, 1.35, e))

        return content
            .scaleEffect(scale)
            .opacity(fade)
            .offset(x: x * pull, y: y * pull)
            .zIndex(Double(-e))
            .allowsHitTesting(fade > 0.3)
    }

    private func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// Axial coordinates on a pointy-top hex grid (rows offset by half a cell).
struct HexCell: Hashable {
    let q: Int, r: Int

    var ring: Int { max(abs(q), abs(r), abs(q + r)) }

    func point(pitch: CGFloat) -> CGPoint {
        CGPoint(x: pitch * (CGFloat(q) + CGFloat(r) / 2), y: pitch * sqrt(3) / 2 * CGFloat(r))
    }

    /// `count` cells starting from the centre, ring by ring, each ring clockwise from the right.
    static func spiral(count: Int) -> [HexCell] {
        var cells = [HexCell(q: 0, r: 0)]
        let directions = [(-1, 1), (-1, 0), (0, -1), (1, -1), (1, 0), (0, 1)]
        var radius = 1
        while cells.count < count {
            var q = radius, r = 0 // start at (radius, 0), the cell to the right
            for (dq, dr) in directions {
                for _ in 0..<radius {
                    cells.append(HexCell(q: q, r: r))
                    q += dq; r += dr
                }
            }
            radius += 1
        }
        return Array(cells.prefix(count))
    }
}

// MARK: - Icon picker

/// Category icon picker: a search field and shuffle button over the honeycomb. The emoji in the middle is
/// the pick; searching fills the honeycomb with matches, best match in the middle.
struct HoneycombIconPicker: View {
    let selected: String
    let defaults: [String]
    let onSelected: (String) -> Void

    @State private var emojis: [String]
    @State private var selection: String?
    @State private var query = ""
    @FocusState private var searching: Bool

    init(selected: String, defaults: [String], onSelected: @escaping (String) -> Void) {
        self.selected = selected
        self.defaults = defaults
        self.onSelected = onSelected
        _emojis = State(initialValue: Self.withSelected(selected, in: defaults))
        _selection = State(initialValue: selected)
    }

    /// The defaults with the current icon moved to the middle cell, so the honeycomb opens balanced
    /// around it instead of scrolled toward one edge.
    private static func withSelected(_ selected: String, in defaults: [String]) -> [String] {
        [selected] + defaults.filter { $0 != selected }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                searchField
                Button {
                    Haptics.light()
                    withAnimation(.spring(duration: 0.7, bounce: 0.2)) { emojis.shuffle() }
                } label: {
                    Image(systemName: "shuffle").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.cwInk)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.cwTrack))
                }
                .buttonStyle(.plain)
                .disabled(emojis.count < 2)
                .accessibilityLabel(tr("随机"))
            }
            ZStack {
                EmojiHoneycomb(emojis: emojis, selection: $selection)
                if emojis.isEmpty {
                    Text(tr("没有找到表情")).cw(IOSText.subheadline, color: .cwMuted).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Sits a little low, clear of the search field.
            .padding(.top, 24)
            // Dragging the honeycomb puts the keyboard away so there is room to browse.
            .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in if searching { searching = false } })
        }
        .onChange(of: query) { _, q in
            let trimmed = q.trimmingCharacters(in: .whitespaces)
            withAnimation(.spring(duration: 0.55, bounce: 0.15)) {
                emojis = trimmed.isEmpty ? Self.withSelected(selection ?? selected, in: defaults) : Self.search(trimmed)
            }
        }
        .onChange(of: selection) { _, now in
            if let now, now != selected { onSelected(now) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Color.cwMuted)
            TextField("", text: $query, prompt: Text(tr("搜索表情")).foregroundStyle(Color.cwMuted))
                .font(.cw(IOSText.body))
                .focused($searching)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searching = false }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.cwMuted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Capsule().fill(Color.cwTrack))
    }

    /// Up to five rings of matches, best first: name hits (the first word of the search text) before
    /// keyword hits, so the strongest match lands in the middle.
    static func search(_ query: String, limit: Int = 91) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        var named: [String] = [], tagged: [String] = [], seen = Set<String>()
        // Latin words match from the start of a word ("cat" finds cat, not appli-cat-ion); Chinese matches anywhere.
        func hit(_ word: String, in text: String) -> Bool {
            guard word.allSatisfy(\.isASCII) else { return text.contains(word) }
            return text.split(separator: " ").contains { $0.hasPrefix(word) }
        }
        for group in emojiGroups {
            for (emoji, text) in group.emojis where !seen.contains(emoji) && words.allSatisfy({ hit($0, in: text) }) {
                seen.insert(emoji)
                let name = text.prefix { $0 != " " }
                if words.allSatisfy({ name.contains($0) }) { named.append(emoji) } else { tagged.append(emoji) }
            }
        }
        return Array((named + tagged).prefix(limit))
    }
}

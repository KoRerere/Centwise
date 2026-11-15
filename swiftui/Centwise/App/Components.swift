import SwiftUI

// MARK: Press feedback

/// iOS press feedback without a highlight: dims while pressed; with `scale` < 1 it also shrinks under
/// the finger and springs back with a small overshoot.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 1
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? (scale == 1 ? 0.45 : 0.8) : 1)
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? .spring(duration: 0.22, bounce: 0) : .spring(duration: 0.45, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A tap target with press feedback, and optionally a long press.
struct Pressable<Content: View>: View {
    var scale: CGFloat = 1
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    @ViewBuilder var content: () -> Content
    @State private var pressed = false

    init(scale: CGFloat = 1, onTap: (() -> Void)?, onLongPress: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.scale = scale; self.onTap = onTap; self.onLongPress = onLongPress; self.content = content
    }

    var body: some View {
        if let onLongPress {
            content()
                .contentShape(Rectangle())
                .opacity(pressed ? 0.45 : 1)
                .animation(.easeOut(duration: 0.09), value: pressed)
                .onTapGesture { onTap?() }
                .onLongPressGesture(minimumDuration: 0.5, perform: onLongPress, onPressingChanged: { pressed = $0 })
        } else {
            Button { onTap?() } label: { content() }
                .buttonStyle(PressStyle(scale: scale))
                .disabled(onTap == nil)
        }
    }
}

// MARK: Surfaces

/// iOS inset-grouped card: plain white (#1C1C1E in dark mode) on the grey canvas.
struct CwCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    var radius: CGFloat = 14
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var scheme

    init(padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16), radius: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.radius = radius; self.content = content
    }

    init(_ all: CGFloat, radius: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.init(padding: EdgeInsets(top: all, leading: all, bottom: all, trailing: all), radius: radius, content: content)
    }

    init(h: CGFloat, v: CGFloat, radius: CGFloat = 14, @ViewBuilder content: @escaping () -> Content) {
        self.init(padding: EdgeInsets(top: v, leading: h, bottom: v, trailing: h), radius: radius, content: content)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.cwCard)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.022), radius: 4, y: 1)
            )
    }
}

extension EdgeInsets {
    static func lrtb(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) -> EdgeInsets { EdgeInsets(top: t, leading: l, bottom: b, trailing: r) }
    static func all(_ v: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: v, bottom: v, trailing: v) }
    static func hv(_ h: CGFloat, _ v: CGFloat) -> EdgeInsets { EdgeInsets(top: v, leading: h, bottom: v, trailing: h) }
}

// MARK: Amounts

/// Amount with a smaller currency sign on the same baseline — Copilot's number style.
struct AmountText: View {
    let cents: Int
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    /// nil = automatic ("−" for negative values); "" = never show a sign.
    var sign: String?
    var color: Color = .cwInk
    /// false: the system font instead of Nunito — for amounts in lists.
    var brand = true

    var body: some View {
        let prefix = sign ?? (cents < 0 ? "−" : "")
        let digits = Money.text(abs(cents), symbol: false)
        Text("\(prefix)\(Text(Money.symbol).font(.cw(size * 0.6, weight, brand: brand)).tracking(size * 0.04))\(digits)")
            .font(.cw(size, weight, brand: brand))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .accessibilityLabel("\(prefix)\(Money.text(abs(cents)))")
    }
}

/// A translated sentence with one money amount in it, e.g. tr("比昨天同期多花 {amount}").
struct TextWithAmount: View {
    let template: String
    let cents: Int
    var size: CGFloat = IOSText.footnote
    var color: Color = .cwMuted
    var amountColor: Color?

    var body: some View {
        let parts = template.components(separatedBy: "{amount}")
        var text = Text("")
        for (i, part) in parts.enumerated() {
            if i > 0 {
                let c = amountColor ?? color
                text = Text("\(text)\(Text(Money.symbol).font(.cw(size * 0.8, .semibold, brand: true)).foregroundStyle(c))\(Text(Money.text(abs(cents), symbol: false)).font(.cw(size, .semibold, brand: true)).foregroundStyle(c))")
            }
            if !part.isEmpty { text = Text("\(text)\(Text(part))") }
        }
        return text.font(.cw(size)).foregroundStyle(color).lineLimit(1)
    }
}

// MARK: Captions

/// Section title above a card: bold Title 3 on the left, a grey "共 n 笔 ›" link on the right.
struct CardCaption: View {
    let title: String
    var trailing: String?
    var onTap: (() -> Void)?

    init(_ title: String, trailing: String? = nil, onTap: (() -> Void)? = nil) {
        self.title = title; self.trailing = trailing; self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).cw(IOSText.title3, .bold).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                if let onTap {
                    Pressable(onTap: onTap) {
                        HStack(spacing: 2) {
                            Text(trailing).cw(IOSText.subheadline, color: .cwMuted)
                            LIcon("chevron-right", size: 14, color: .cwMuted.opacity(0.8))
                        }
                    }
                } else {
                    Text(trailing).cw(IOSText.subheadline, color: .cwMuted)
                }
            }
        }
    }
}

// MARK: Budget

struct BudgetBar: View {
    let ratio: Double
    var height: CGFloat = 7
    var color: Color?

    var body: some View {
        let clamped = ratio.isNaN ? 0 : min(max(ratio, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.cwTrack)
                Capsule().fill(color ?? .budget(ratio)).frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// "已用 60% · 正常" under a budget bar.
struct BudgetUsageLine: View {
    let ratio: Double
    var body: some View {
        let percent = ratio.isNaN || ratio.isInfinite ? 0 : Int((ratio * 100).rounded())
        let (status, color): (String, Color) = ratio >= 1 ? (tr("已超出预算"), .cwOver) : ratio >= 0.8 ? (tr("接近上限"), .cwWarning) : (tr("正常"), .cwUnder)
        HStack(spacing: 5) {
            Text(tr("已用 {percent}%", ["percent": percent])).cw(IOSText.footnote, color: .cwMuted)
            Spacer()
            Circle().fill(color).frame(width: 6, height: 6)
            Text(status).cw(IOSText.footnote)
        }
    }
}

// MARK: Bottom controls

/// Height of the floating period capsule / 记一笔 row (without the home-indicator inset).
let bottomControlsHeight: CGFloat = 68

/// Small spring "pop" each time `selected` turns on.
struct SelectPop: ViewModifier {
    let selected: Bool
    @State private var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scaleEffect(scale)
            .onChange(of: selected) { _, now in
                guard now, !reduceMotion else { return }
                scale = 0.86
                withAnimation(.spring(duration: 0.42, bounce: 0.45)) { scale = 1 }
            }
    }
}

extension View {
    func selectPop(_ selected: Bool) -> some View { modifier(SelectPop(selected: selected)) }
}

/// Item frames reported to a PillTrack.
struct PillFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// The selection pill: interpolates between item frames at a fractional position (animatable).
struct PillShape: Shape {
    var position: Double
    var frames: [CGRect]
    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard !frames.isEmpty else { return Path() }
        let p = min(max(position, 0), Double(frames.count - 1))
        let i = Int(p.rounded(.down)), j = min(i + 1, frames.count - 1)
        let t = CGFloat(p - Double(i))
        let a = frames[i], b = frames[j]
        let r = CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                       width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
        return Path(roundedRect: r, cornerRadius: r.height / 2, style: .continuous)
    }
}

/// A row of items with one pill-shaped highlight behind them that glides between items.
/// `itemBuilder` gets each item's selectedness (1 = under the pill, 0 = a full item away).
struct PillTrack<Item: View, Fill: ShapeStyle>: View {
    let count: Int
    let position: Double
    var spacing: CGFloat = 0
    let fill: Fill
    var shadow = false
    @ViewBuilder let item: (Int, Double) -> Item
    @State private var frames: [Int: CGRect] = [:]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { i in
                item(i, max(0, 1 - abs(position - Double(i))))
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: PillFramesKey.self, value: [i: geo.frame(in: .named("pilltrack"))])
                    })
            }
        }
        .background {
            let list = (0..<count).compactMap { frames[$0] }
            if list.count == count {
                PillShape(position: position, frames: list)
                    .fill(fill)
                    .shadow(color: .black.opacity(shadow ? 0.16 : 0), radius: 3, y: 2)
            }
        }
        .coordinateSpace(.named("pilltrack"))
        .onPreferenceChange(PillFramesKey.self) { value in
            if value != frames { frames = value }
        }
    }
}

/// 今天 / 本月 / 今年 with step arrows, on Liquid Glass.
struct PeriodCapsule: View {
    @Environment(LedgerStore.self) private var store
    private static let periods: [Period] = [.day, .month, .year]
    /// Segment frames in the "periodSegments" space.
    @State private var frames: [Int: CGRect] = [:]
    /// Finger down on the segments: the thumb turns into an iOS 26 Liquid Glass lens that follows it.
    @State private var pressed = false
    @State private var fingerX: CGFloat = 0
    @State private var hover: Int?

    private var selectedIndex: Int { Self.periods.firstIndex(of: store.period) ?? 0 }

    private func index(at x: CGFloat) -> Int {
        var best = selectedIndex, distance = CGFloat.infinity
        for (i, f) in frames where abs(f.midX - x) < distance { best = i; distance = abs(f.midX - x) }
        return best
    }

    var body: some View {
        let fallbacks = [tr("今天"), tr("本月"), tr("今年")]
        let active = hover ?? selectedIndex
        HStack(spacing: 0) {
            arrow(-1)
            HStack(spacing: 0) {
                ForEach(Array(Self.periods.enumerated()), id: \.offset) { i, period in
                    let selected = store.period == period
                    let label = selected ? store.periodName : fallbacks[i]
                    let color: Color = pressed ? (i == active ? .cwInk : .cwMuted) : (selected ? .cwOnBrand : .cwMuted)
                    Text(label)
                        .cw(14, .semibold, color: color)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .padding(.horizontal, 11)
                        .frame(minWidth: 50)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("periodSegments")) } action: { rect in
                            if frames[i] == nil { frames[i] = rect } else { withAnimation(IOSMotion.snappy) { frames[i] = rect } }
                        }
                        .animation(.easeOut(duration: 0.18), value: color)
                        .animation(.easeOut(duration: 0.22), value: label)
                        .accessibilityElement()
                        .accessibilityLabel(label)
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { select(i) }
                }
            }
            // At rest: the black thumb under the labels.
            .background(alignment: .topLeading) {
                if let f = frames[selectedIndex] {
                    Capsule()
                        .fill(LinearGradient(stops: [
                            .init(color: Color.cwBrand.mix(with: .white, by: 0.16), location: 0),
                            .init(color: .cwBrand, location: 0.5), .init(color: .cwBrand, location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                        .opacity(pressed ? 0 : 1)
                }
            }
            // Pressed: a clear glass lens over the labels, a little larger, sliding with the finger.
            .overlay(alignment: .topLeading) {
                if pressed, let f = frames[active] {
                    let w = f.width + 14, h = f.height + 14
                    let lo = (frames.values.map(\.minX).min() ?? 0) + w / 2 - 7
                    let hi = (frames.values.map(\.maxX).max() ?? 0) - w / 2 + 7
                    let cx = min(max(fingerX, lo), max(lo, hi))
                    let i = active
                    let text = Self.periods[i] == store.period ? store.periodName : fallbacks[i]
                    // The lens magnifies the label it sits on, like iOS 26's segmented control.
                    Color.clear
                        .frame(width: w, height: h)
                        .glassEffect(.clear.interactive(), in: .capsule)
                        .overlay {
                            Text(text)
                                .cw(14, .semibold)
                                .lineLimit(1)
                                .fixedSize()
                                .scaleEffect(1.18)
                                .contentTransition(.opacity)
                        }
                        .offset(x: cx - w / 2, y: f.midY - h / 2)
                        .allowsHitTesting(false)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .coordinateSpace(.named("periodSegments"))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("periodSegments"))
                .onChanged { v in
                    fingerX = v.location.x
                    if !pressed {
                        Haptics.light()
                        withAnimation(.spring(duration: 0.3, bounce: 0.3)) { pressed = true }
                    }
                    let i = index(at: v.location.x)
                    if i != active { Haptics.selection() }
                    withAnimation(.spring(duration: 0.25, bounce: 0.2)) { hover = i }
                }
                .onEnded { v in
                    let i = index(at: v.location.x)
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                        pressed = false
                        hover = nil
                    }
                    select(i)
                })
            arrow(1)
        }
        .padding(4)
        // iOS 26 Liquid Glass: refracts the cards scrolling behind it.
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func select(_ i: Int) {
        let period = Self.periods[i]
        if store.period != period { Haptics.selection() }
        withAnimation(IOSMotion.snappy) { store.select(period) }
    }

    private func stepLabel(_ v: Int) -> String {
        switch store.period {
        case .day: v < 0 ? tr("前一天") : tr("后一天")
        case .month: v < 0 ? tr("上个月") : tr("下个月")
        case .year: v < 0 ? tr("前一年") : tr("后一年")
        }
    }

    private func arrow(_ value: Int) -> some View {
        Pressable(onTap: { withAnimation(IOSMotion.smooth) { store.stepPeriod(value) } }) {
            LIcon(value < 0 ? "chevron-left" : "chevron-right", size: 16, color: .cwInk, strokeWidth: 2.5)
                .frame(width: 30, height: 36)
        }
        .accessibilityLabel(stepLabel(value))
    }
}

/// Round black ＋ that floats over the pages.
struct FloatingCircleButton: View {
    let icon: String
    let label: String
    var onTap: (() -> Void)?

    var body: some View {
        Pressable(scale: 0.88, onTap: onTap) {
            Circle().fill(Color.cwBrand)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                .overlay(LIcon(icon, size: 24, color: .cwOnBrand, strokeWidth: 2.5))
        }
        .accessibilityLabel(label)
    }
}

/// Full-width black capsule button (保存这笔支出 …).
struct PrimaryBarButton: View {
    let label: String
    var icon: String?
    var onTap: (() -> Void)?

    var body: some View {
        let enabled = onTap != nil
        Pressable(scale: 0.97, onTap: onTap) {
            HStack(spacing: 6) {
                if let icon { LIcon(icon, size: 18, color: .cwOnBrand, strokeWidth: 2.5) }
                Text(label).cw(17, .medium, color: Color.cwOnBrand.opacity(enabled ? 1 : 0.85))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Capsule().fill(enabled ? Color.cwBrand : Color.cwMuted.opacity(0.35)))
            .animation(IOSMotion.snappy, value: enabled)
        }
    }
}

/// iOS segmented control (the system's own).
struct CapsuleSegments<T: Hashable>: View {
    let values: [T]
    let selected: T
    let label: (T) -> String
    let onChanged: (T) -> Void

    var body: some View {
        Picker("", selection: Binding(get: { selected }, set: { v in
            if v != selected { Haptics.selection() }
            onChanged(v)
        })) {
            ForEach(values, id: \.self) { v in Text(label(v)).tag(v) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: Content transition (period changes)

/// Content fades up from 35 % and drifts 8 pt when `trigger` changes.
struct ContentTransition: ViewModifier {
    let trigger: String
    @State private var t: Double = 1

    func body(content: Content) -> some View {
        content
            .opacity(0.35 + 0.65 * t)
            .offset(y: (1 - t) * 8)
            .onChange(of: trigger) {
                t = 0
                withAnimation(IOSMotion.smooth) { t = 1 }
            }
    }
}

// MARK: Undo toast

/// "已删除账单 · 撤销", floating above the bottom controls.
struct UndoDeleteToast: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let count = store.recentlyDeleted.count
        ZStack {
            if count > 0 {
                HStack(spacing: 8) {
                    LIcon("trash", size: 16, color: .white.opacity(0.7))
                    Text(count == 1 ? tr("已删除账单") : tr("已删除 {n} 笔账单", ["n": count]))
                        .cw(14, color: .white).lineLimit(1)
                    Spacer(minLength: 10).frame(maxWidth: 10)
                    Pressable(onTap: {
                        Haptics.selection()
                        withAnimation(IOSMotion.smooth) { _ = store.undoDelete() }
                    }) {
                        HStack(spacing: 4) {
                            LIcon("undo-2", size: 15, color: .white, strokeWidth: 2.5)
                            Text(tr("撤销")).cw(14, .bold, color: .white)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 9)
                    }
                    .accessibilityLabel(tr("撤销删除"))
                }
                .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 4)
                .frame(maxWidth: 360)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(scheme == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0x0A0A0A)))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                .transition(.opacity.combined(with: .offset(y: 20)))
            }
        }
        .animation(count > 0 ? IOSMotion.bouncy : IOSMotion.smooth, value: count > 0)
    }
}

// MARK: Bill rows

/// The round dashed frame a bill's icon sits in, with the parent category as a small badge.
struct BillIcon<Content: View>: View {
    var badge: LedgerCategory?
    var size: CGFloat = 46
    @ViewBuilder var content: () -> Content

    static var textInset: CGFloat { 58 }

    var body: some View {
        // Plain emoji, no dashed ring.
        content()
            .frame(width: size, height: size)
        .overlay(alignment: .bottomLeading) {
            if let badge {
                Circle().fill(Color.cwCard)
                    .overlay(Circle().fill(categoryTint(badge.id).opacity(0.22)))
                    .overlay(Circle().stroke(Color.cwCard, lineWidth: 1.5))
                    .frame(width: 22, height: 22)
                    .overlay(CategoryIcon(badge, size: 13.5))
                    .offset(x: -2, y: 2)
            }
        }
    }
}

let billTextInset: CGFloat = 58

struct DashedRing: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - 0.6
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dashes = 22
        let sweep = 2 * Double.pi / Double(dashes)
        for i in 0..<dashes {
            let a = Double(i) * sweep
            p.move(to: CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
            p.addArc(center: center, radius: radius, startAngle: .radians(a), endAngle: .radians(a + sweep * 0.55), clockwise: false)
        }
        return p
    }
}

struct RowDivider: View {
    var indent: CGFloat = billTextInset
    var body: some View { Rectangle().fill(Color.cwStroke).frame(height: hairline).padding(.leading, indent) }
}

struct DashedDivider: View {
    var body: some View {
        Line().stroke(Color.cwStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
    }
    struct Line: Shape {
        func path(in rect: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: rect.width, y: 0.5)); return p }
    }
}

/// "今天" / "昨天" / "10月13日 星期二".
enum DayHeading {
    static func label(_ day: Date) -> String {
        let difference = Cal.daysBetween(day, Date())
        if difference == 0 { return tr("今天") }
        if difference == 1 { return tr("昨天") }
        return fmtDayHeading(day)
    }
}

struct DayHeadingView: View {
    let day: Date
    var body: some View { Text(DayHeading.label(day)).cw(IOSText.footnote, color: .cwMuted).frame(maxWidth: .infinity, alignment: .leading) }
}

func groupedByDay(_ entries: [Entry]) -> [(Date, [Entry])] {
    var result: [(Date, [Entry])] = []
    for entry in entries {
        let day = Cal.dateOnly(entry.date)
        if let last = result.last, last.0 == day { result[result.count - 1].1.append(entry) } else { result.append((day, [entry])) }
    }
    return result
}

/// One bill: icon, category (› subcategory), note, amount. Swipe left to delete, long press for actions.
struct EntryRow: View {
    @Environment(LedgerStore.self) private var store
    let entry: Entry
    var showDate = false
    var onTap: (() -> Void)?
    @State private var askDelete = false

    var body: some View {
        let category = entry.allocations.count == 1 ? store.category(entry.allocations[0].categoryID) : nil
        let title = title(category)
        SwipeToDelete(id: entry.id, onDelete: { store.deleteEntry(entry) }) {
            Pressable(onTap: onTap, onLongPress: {
                Haptics.medium()
                askDelete = true
            }) {
                rowContent(category, title)
            }
        }
        .confirmationDialog(title, isPresented: $askDelete, titleVisibility: .visible) {
            Button(tr("删除记录"), role: .destructive) { withAnimation(IOSMotion.smooth) { _ = store.deleteEntry(entry) } }
            Button(tr("取消"), role: .cancel) {}
        }
    }

    private func title(_ category: LedgerCategory?) -> String {
        switch entry.kind {
        case .transfer: return tr("转账")
        case .adjustment: return tr("余额调整")
        default:
            if let category {
                if let parent = store.category(category.parentID) { return "\(parent.name) › \(category.name)" }
                return category.name
            }
            return entry.allocations.count > 1 ? tr("{n} 项分摊", ["n": entry.allocations.count]) : store.categoryName(entry)
        }
    }

    private func details(_ memo: String) -> [String] {
        var details: [String] = []
        if entry.kind == .transfer {
            details.append("\(store.accountName(entry.accountID)) → \(entry.destinationID.map { store.accountName($0) } ?? "—")")
        } else if entry.kind == .adjustment {
            details.append(store.accountName(entry.accountID))
        }
        if !memo.isEmpty { details.append(memo) }
        if showDate { details.append(fmtMonthDay(entry.date)) }
        if entry.pending { details.append(tr("待入账")) }
        if entry.needsReview { details.append(tr("待核对")) }
        return details
    }

    @ViewBuilder
    private func rowContent(_ category: LedgerCategory?, _ title: String) -> some View {
        let memo = entry.note.isEmpty ? entry.payee : entry.note
        let sign: String = {
            switch entry.kind {
            case .expense: entry.amount < 0 ? "+" : ""
            case .income: entry.amount < 0 ? "−" : "+"
            case .transfer: ""
            case .adjustment: entry.amount < 0 ? "−" : "+"
            }
        }()
        let amountColor: Color = (entry.kind == .income && entry.amount > 0) || (entry.kind == .expense && entry.amount < 0)
            ? .cwIncome : (entry.kind == .adjustment ? .cwMuted : .cwInk)
        let info = details(memo)
        HStack(spacing: 12) {
            if let category, entry.kind.isFlow {
                BillIcon(badge: store.category(category.parentID)) { CategoryIcon(category, size: 30) }
            } else {
                BillIcon { LIcon(entry.kind == .transfer ? "arrow-left-right" : (entry.kind == .adjustment ? "equal" : "split"), size: 19, color: .cwMuted) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cw(IOSText.body).lineLimit(1)
                if !info.isEmpty {
                    Text(info.joined(separator: " · ")).cw(14, color: entry.needsReview ? .cwOver : .cwMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            AmountText(cents: entry.amount, size: IOSText.body, weight: .semibold, sign: sign, color: amountColor, brand: false)
                .fixedSize()
        }
        .padding(.vertical, 11)
        .background(Color.cwCard)
    }
}

// MARK: Currency

struct CurrencyLabel: View {
    let code: String
    var color: Color = .cwMuted
    var body: some View {
        let c = currencyFor(code)
        HStack(spacing: 6) {
            FlagIcon(code: c.flag, size: 18)
            Text("\(c.name) \(c.code)").cw(IOSText.body, color: color)
        }
    }
}

// MARK: Empty state

/// Empty placeholder: three small icon cards fanning out over a dot grid, a title, a line and a button.
struct EmptyState: View {
    let icon: String
    let title: String
    var illustration: String?
    var message: String?
    var actionLabel: String?
    var onAction: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var shown = false

    private static let symbolFor = ["receipt": "receipt", "search": "search", "wallet": "chart-pie"]

    var body: some View {
        let symbol = illustration.flatMap { Self.symbolFor[$0] } ?? icon
        let companions = Array(["chart-pie", "calendar", "receipt"].filter { $0 != symbol }.prefix(2))
        VStack(spacing: 0) {
            ZStack {
                card(companions[0], shade: 1.0)
                    .scaleEffect(shown ? 1 : 0.6)
                    .rotationEffect(.radians(shown ? -0.18 : 0))
                    .offset(x: shown ? -40 : 0, y: shown ? 8 : -4)
                    .animation(.spring(duration: 0.5, bounce: 0.42).delay(0.06), value: shown)
                card(companions[1], shade: 0.72)
                    .scaleEffect(shown ? 1 : 0.6)
                    .rotationEffect(.radians(shown ? 0.18 : 0))
                    .offset(x: shown ? 40 : 0, y: shown ? 8 : -4)
                    .animation(.spring(duration: 0.5, bounce: 0.42).delay(0.11), value: shown)
                card(symbol, shade: 0.6)
                    .offset(y: -4)
                    .scaleEffect(shown ? 1 : 0.82)
                    .animation(.spring(duration: 0.42, bounce: 0.45), value: shown)
            }
            .frame(height: 84)
            Text(title).cw(IOSText.headline, .semibold).multilineTextAlignment(.center).padding(.top, 10)
            if let message {
                Text(message).cw(IOSText.subheadline, color: .cwMuted).multilineTextAlignment(.center).lineSpacing(3).padding(.top, 4)
            }
            if let actionLabel, let onAction {
                Pressable(onTap: onAction) {
                    HStack(spacing: 6) {
                        LIcon("plus", size: 15)
                        Text(actionLabel).cw(IOSText.subheadline, .semibold)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.cwRaised))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cwStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 3, y: 2)
                }
                .padding(.top, 16)
            }
        }
        .padding(.vertical, 34).padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(DotGrid().fill((scheme == .dark ? Color.white : Color.black).opacity(0.16)))
        .onAppear { shown = true }
    }

    private func card(_ name: String, shade: Double) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.cwRaised)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cwStroke, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 3, y: 2)
            .frame(width: 54, height: 54)
            .overlay(LIcon(name, size: 25, color: Color.cwInk.opacity(shade), strokeWidth: 1.8))
    }
}

struct DotGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let spacing: CGFloat = 16
        var y = spacing / 2
        while y < rect.height {
            var x = spacing / 2
            while x < rect.width {
                p.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                x += spacing
            }
            y += spacing
        }
        return p
    }
}

/// The frosted strip behind an editor's bottom bar, fading into the content above it.
struct BottomBarBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.cwCanvas.opacity(0.72))
            LinearGradient(colors: [Color.cwCanvas.opacity(0), Color.cwCanvas.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .frame(height: 46).offset(y: -46)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

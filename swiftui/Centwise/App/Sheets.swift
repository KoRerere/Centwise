import SwiftUI

extension Color {
    /// Sheet surface: Flutter's frosted glass sheet (#F9F9FB at 70 % over a lifted blur) settles at
    /// about #F7F7F9 over the canvas; near-black in dark mode.
    static let cwSheet = Color(lightHex: 0xF7F7F9, darkHex: 0x0A0A0B)
}

// MARK: Presentation depth (so alerts and the import preview show above whatever sheet is open)

@Observable final class PresentationTracker {
    static let shared = PresentationTracker()
    var top = 0
}

private struct SheetDepthKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var sheetDepth: Int {
        get { self[SheetDepthKey.self] }
        set { self[SheetDepthKey.self] = newValue }
    }
}

enum SheetStyle {
    /// Full-height glass sheet, 32 pt corners.
    case glass
    /// Short white card (option lists, the date wheel), 18 pt corners.
    case card
    /// Like glass, but the content draws its own background so it can follow a drag (DragToCloseSheet).
    case draggable
}

/// Dimming behind a sheet; the presenter fades it with the sheet's slide.
@Observable final class PanelDim {
    var shown = false
}

/// A sheet's content can ask to confirm before a pull closes it (see `GuardedSheetDismiss`).
@Observable final class PanelCloseGuard {
    @ObservationIgnored var onAttempt: (() -> Void)?
}

/// Height of the on-screen keyboard, so a sheet can keep its place and pad its content instead.
@Observable final class KeyboardObserver {
    static let shared = KeyboardObserver()
    private(set) var height: CGFloat = 0

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let value = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.easeOut(duration: 0.25)) { self?.height = value }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            withAnimation(.easeOut(duration: 0.25)) { self?.height = 0 }
        }
    }
}

private struct PanelCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    /// Closes the enclosing sheet the way a pull down does (asking its guard first).
    var panelClose: (() -> Void)? {
        get { self[PanelCloseKey.self] }
        set { self[PanelCloseKey.self] = newValue }
    }
}

/// Root of every sheet: a panel attached to the screen's bottom and side edges, inside a clear
/// full-screen cover (see `PanelPresenter`). It tracks depth, sets the sheet look and hosts store
/// alerts. Without a `height` the panel is as tall as a system sheet at 94 %.
struct SheetHost<Content: View>: View {
    var height: CGFloat?
    var style: SheetStyle = .glass
    var dim: PanelDim?
    @ViewBuilder var content: () -> Content
    @Environment(\.sheetDepth) private var parentDepth
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var drag: CGFloat = 0
    @State private var closeGuard = PanelCloseGuard()

    private func attemptClose() {
        if let attempt = closeGuard.onAttempt { attempt() } else { dismiss() }
    }

    private var panel: some View {
        let fill = style == .card ? Color.cwCard : Color.cwSheet
        let radius: CGFloat = style == .card ? 18 : 32
        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)
        return GeometryReader { geo in
            let screen = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            // Where a system sheet's 94 % detent puts its top edge.
            let full = 8 + 0.94 * (screen - geo.safeAreaInsets.top - 30) - geo.safeAreaInsets.bottom
            let panelHeight = min(height ?? full, full)
            VStack(spacing: 0) {
                Color.clear.contentShape(Rectangle()).onTapGesture { if height != nil { attemptClose() } }.accessibilityHidden(true)
                content()
                    .safeAreaPadding(.bottom, max(0, KeyboardObserver.shared.height - geo.safeAreaInsets.bottom))
                    .frame(maxWidth: .infinity)
                    .frame(height: panelHeight)
                    .background(fill)
                    // Rounded top only: the content's own bottom bar may run into the home-indicator strip.
                    .mask(alignment: .top) { shape.frame(height: panelHeight + 600) }
                    // Runs past the bottom so that strip stays filled, also mid-drag.
                    .background(alignment: .top) { shape.fill(fill).frame(height: panelHeight + 600) }
                    .offset(y: drag)
                    .gesture(DragGesture(minimumDistance: 12)
                        .onChanged { drag = $0.translation.height > 0 ? $0.translation.height : $0.translation.height / 8 }
                        .onEnded { g in
                            let far = g.translation.height > panelHeight / 3 || g.predictedEndTranslation.height - g.translation.height > 300
                            if far && closeGuard.onAttempt == nil {
                                dismiss()
                            } else {
                                withAnimation(IOSMotion.snappy) { drag = 0 }
                                if far { attemptClose() }
                            }
                        })
            }
        }
        // The panel keeps its place when the keyboard shows; its content is padded instead.
        .ignoresSafeArea(.keyboard)
        // Taller than the screen so it already covers everything while the cover slides in.
        .background(alignment: .bottom) {
            Color.black.opacity(dim?.shown == true ? 0.24 : 0).frame(height: 4000).offset(y: 200).allowsHitTesting(false)
        }
    }

    var body: some View {
        let depth = parentDepth + 1
        panel
            .presentationBackground(.clear)
            .environment(\.sheetDepth, depth)
            .environment(\.panelClose, attemptClose)
            .environment(closeGuard)
            .modifier(StoreOverlays(depth: depth))
            .preferredColorScheme(store.colorScheme)
            .onAppear { PresentationTracker.shared.top = depth }
            .onDisappear { PresentationTracker.shared.top = depth - 1 }
    }
}

/// Presents a sheet as a panel attached to the screen's edges. iOS 26 floats every system sheet
/// shorter than `.large` away from the edges, so sheets use a clear full-screen cover instead.
private struct PanelPresenter<Item: Identifiable, PanelContent: View>: ViewModifier {
    @Binding var item: Item?
    let height: (Item) -> CGFloat?
    let style: SheetStyle
    @ViewBuilder let panel: (Item) -> PanelContent
    @State private var dim = PanelDim()

    func body(content: Content) -> some View {
        content
            .onChange(of: item != nil, initial: true) { _, on in
                withAnimation(.easeOut(duration: on ? 0.3 : 0.22)) { dim.shown = on }
            }
            .fullScreenCover(item: $item) { value in
                SheetHost(height: height(value), style: style, dim: dim) { panel(value) }
            }
    }
}

private struct PanelFlag: Identifiable { let id = 0 }

extension View {
    func cwSheet<Content: View>(isPresented: Binding<Bool>, height: CGFloat? = nil, style: SheetStyle = .glass,
                                @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(PanelPresenter(item: Binding<PanelFlag?>(get: { isPresented.wrappedValue ? PanelFlag() : nil },
                                                          set: { if $0 == nil { isPresented.wrappedValue = false } }),
                                height: { _ in height }, style: style, panel: { _ in content() }))
    }

    func cwSheet<Item: Identifiable, Content: View>(item: Binding<Item?>, height: ((Item) -> CGFloat?)? = nil, style: SheetStyle = .glass,
                                                    @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(PanelPresenter(item: item, height: { height?($0) }, style: style, panel: content))
    }
}

/// Errors and import previews, presented from the top-most level.
struct StoreOverlays: ViewModifier {
    let depth: Int
    @Environment(LedgerStore.self) private var store
    private var tracker: PresentationTracker { PresentationTracker.shared }

    func body(content: Content) -> some View {
        let isTop = tracker.top == depth
        content
            .cwAlert(Binding(get: {
                guard isTop, let error = store.error else { return nil }
                return CwAlert(id: "error|\(error)", title: tr("操作未完成"), message: error,
                               actions: [CwAlertAction(label: tr("知道了"), prominent: true, action: { store.error = nil })])
            }, set: { if $0 == nil && isTop { store.error = nil } }))
            .cwSheet(isPresented: Binding(get: { isTop && store.pendingImport != nil }, set: { if !$0 { store.cancelImport() } })) {
                ImportPreview()
            }
    }
}

// MARK: Alerts (Centwise's own: left-aligned text, capsule buttons, black prominent one)

struct CwAlertAction: Identifiable {
    let id = UUID()
    let label: String
    var prominent = false
    var destructive = false
    var action: () -> Void = {}
}

struct CwAlert: Identifiable {
    var id: String = UUID().uuidString
    let title: String
    var message: String?
    var actions: [CwAlertAction]

    /// One "知道了" button.
    static func info(title: String, message: String) -> CwAlert {
        CwAlert(title: title, message: message, actions: [CwAlertAction(label: tr("知道了"), prominent: true)])
    }

    /// 放弃本次修改？ — 继续编辑 / 放弃修改.
    static func discard(_ onDiscard: @escaping () -> Void) -> CwAlert {
        CwAlert(title: tr("放弃本次修改？"), message: tr("已输入的内容不会保存。"), actions: [
            CwAlertAction(label: tr("继续编辑"), prominent: true),
            CwAlertAction(label: tr("放弃修改"), destructive: true, action: onDiscard),
        ])
    }
}

extension View {
    func cwAlert(_ alert: Binding<CwAlert?>) -> some View { modifier(CwAlertPresenter(alert: alert)) }
}

/// Shows a CwAlert in a clear full-screen cover (so it sits above any sheet) and runs the picked
/// action once the cover is gone.
struct CwAlertPresenter: ViewModifier {
    @Binding var alert: CwAlert?
    @State private var shown: CwAlert?

    private func set(_ value: CwAlert?) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { shown = value }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: alert?.id, initial: true) { _, id in
                if id != nil && shown?.id != id { set(alert) }
                if id == nil && shown != nil { set(nil) }
            }
            .fullScreenCover(item: $shown) { a in
                CwAlertView(alert: a) { picked in
                    set(nil)
                    alert = nil
                    if let picked { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { picked.action() } }
                }
                .presentationBackground(.clear)
            }
    }
}

struct CwAlertView: View {
    let alert: CwAlert
    let finish: (CwAlertAction?) -> Void
    @State private var shown = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stacked = alert.actions.count > 2 || alert.actions.contains { $0.label.count > 6 }
        ZStack {
            Color.black.opacity(shown ? 0.28 : 0).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(alert.title).cw(IOSText.headline, .semibold).fixedSize(horizontal: false, vertical: true)
                if let message = alert.message {
                    Text(message).cw(IOSText.subheadline, color: .cwMuted).lineSpacing(3).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if stacked {
                        VStack(spacing: 8) { ForEach(alert.actions) { button($0) } }
                    } else {
                        HStack(spacing: 10) { ForEach(alert.actions) { button($0) } }
                    }
                }
                .padding(.top, 22)
            }
            .padding(.top, 24).padding(.horizontal, 24).padding(.bottom, 20)
            .frame(maxWidth: 340, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(scheme == .dark ? Color(hex: 0x1C1C1E, alpha: 0.92) : Color(hex: 0xF9F9FB, alpha: 0.94)))
                    .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.14), radius: 18, y: 12)
            )
            .padding(.horizontal, 32)
            .scaleEffect(shown ? 1 : 1.12)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(IOSMotion.bouncy) { shown = true } }
    }

    private func button(_ a: CwAlertAction) -> some View {
        Pressable(onTap: {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.2)) { shown = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { finish(a) }
        }) {
            Text(a.label)
                .cw(IOSText.body, .semibold, color: a.prominent ? .cwOnBrand : (a.destructive ? .cwOver : .cwInk))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(a.prominent ? Color.cwBrand : Color.cwTrack))
        }
    }
}

// MARK: Sheet scaffold

/// Scroll views inside a sheet report their offset so the bar can frost and the large title collapse.
struct SheetScrollReporter { let report: (CGFloat) -> Void }

private struct SheetScrollKey: EnvironmentKey { static let defaultValue: SheetScrollReporter? = nil }
extension EnvironmentValues {
    var sheetScroll: SheetScrollReporter? {
        get { self[SheetScrollKey.self] }
        set { self[SheetScrollKey.self] = newValue }
    }
}

private struct ReportsSheetScroll: ViewModifier {
    @Environment(\.sheetScroll) private var reporter
    @Environment(\.panelClose) private var close
    @State private var pull: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                reporter?.report(y)
                if y < 0 || pull != 0 { pull = max(0, -y) }
            }
            // Like a system sheet: a long pull down past the top closes it.
            .onScrollPhaseChange { old, phase in
                if old == .interacting && phase != .interacting && pull > 110 { close?() }
            }
    }
}

extension View {
    /// Put on a sheet's ScrollView: drives the frosted bar and the large-title collapse.
    func sheetScroll() -> some View { modifier(ReportsSheetScroll()) }
}

/// A sheet's chrome, as in the Flutter version: a 68 pt bar with round white glass buttons.
///  - leading "返回" → chevron on the left
///  - with a trailing label (保存) → ✕ on the left, the label on the right
///  - "完成" → a text capsule on the right; otherwise ✕ on the right
/// Content scrolls up under the bar, which frosts once it does.
struct SheetScaffold<Content: View>: View {
    let title: String
    var leadingLabel: String?
    var onLeading: (() -> Void)?
    var trailingLabel: String?
    var onTrailing: (() -> Void)?
    var showsTitle = true
    var largeTitle = false
    var closeButton = true
    /// Content starts at the very top (behind the bar's buttons) instead of below the bar.
    var contentUnderBar = false
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var offset: CGFloat = 0

    static var barHeight: CGFloat { 68 }
    static var largeTitleCollapseAt: CGFloat { 30 }

    var body: some View {
        let start: CGFloat = largeTitle ? Self.largeTitleCollapseAt : 0
        let amount = min(max((offset - start) / 16, 0), 1)
        content()
            .environment(\.sheetScroll, SheetScrollReporter { y in if abs(y - offset) > 0.5 { offset = y } })
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: largeTitle || contentUnderBar ? 0 : Self.barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.cwSheet.ignoresSafeArea())
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if amount > 0 {
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(LinearGradient(colors: scheme == .dark
                                                    ? [Color.cwCanvas.opacity(0.62 * amount), Color.cwCanvas.opacity(0.48 * amount)]
                                                    : [Color.white.opacity(0.62 * amount), Color(hex: 0xF7F7F9).opacity(0.42 * amount)],
                                                    startPoint: .top, endPoint: .bottom))
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity((scheme == .dark ? 0.35 : 0.08) * amount)).frame(height: hairline) }
                            .opacity(amount)
                            .frame(height: Self.barHeight)
                            .allowsHitTesting(false)
                    }
                    bar
                }
            }
    }

    private var bar: some View {
        let label = leadingLabel ?? tr("取消")
        let action = onLeading ?? { dismiss() }
        let isBack = label == tr("返回")
        let isDone = label == tr("完成")
        let collapsed = offset > Self.largeTitleCollapseAt
        return ZStack {
            if largeTitle {
                Text(title).cw(IOSText.headline, .semibold).lineLimit(1).padding(.horizontal, 96)
                    .opacity(collapsed ? 1 : 0)
                    .offset(y: collapsed ? 0 : -14)
                    .animation(collapsed ? .spring(duration: 0.38, bounce: 0.3) : .easeIn(duration: 0.22), value: collapsed)
            } else if showsTitle {
                Text(title).cw(IOSText.headline, .semibold).lineLimit(1).padding(.horizontal, 96)
                    .id(title)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.22), value: title)
            }
            HStack(spacing: 0) {
                if isBack {
                    GlassBarButton(icon: "chevron-left", onTap: action).accessibilityLabel(label)
                } else if closeButton && trailingLabel != nil {
                    GlassBarButton(icon: "x", onTap: action).accessibilityLabel(label)
                }
                Spacer(minLength: 0)
                if let trailingLabel {
                    GlassBarButton(label: trailingLabel, emphasized: true, onTap: onTrailing)
                } else if closeButton && !isBack {
                    if isDone {
                        GlassBarButton(label: label, onTap: action)
                    } else {
                        GlassBarButton(icon: "x", onTap: action).accessibilityLabel(label)
                    }
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// Round (or capsule, for a text label) white button in a sheet's bar.
struct GlassBarButton: View {
    var icon: String?
    var label: String?
    var emphasized = false
    var onTap: (() -> Void)?

    var body: some View {
        // The system iOS 26 glass button (the same one the system toolbars use): translucent glass with a lit
        // rim that swells, brightens and wobbles under the finger.
        let color: Color = onTap == nil ? .cwMuted : .cwInk
        Button { onTap?() } label: {
            if let icon {
                LIcon(icon, size: 19, color: color, strokeWidth: 2.5)
                    .frame(width: 18, height: 18)
            } else {
                Text(label ?? "").cw(IOSText.body, emphasized ? .semibold : .medium, color: color)
                    .padding(.horizontal, 4)
                    .frame(height: 18)
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(icon != nil ? .circle : .capsule)
        .controlSize(.large)
        .disabled(onTap == nil)
    }
}

/// Moving between two levels inside one sheet (a category and its subcategories): the new page
/// drifts in a quarter width from the side and fades in, the old one fades out.
enum PushMotion {
    static let animation = Animation.timingCurve(0.2, 0.8, 0.25, 1.0, duration: 0.38)
    static func transition(_ direction: CGFloat) -> AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: 90 * direction)),
                    removal: .opacity.combined(with: .offset(x: -60 * direction)))
    }
}

// MARK: Forms (iOS inset-grouped rows on Centwise cards)

extension ContainerValues {
    @Entry var dividerInset: CGFloat = 0
}

/// An inset-grouped card of rows with hairline separators, an optional caption and footer.
struct FormSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.footer = footer; self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title { Text(title).cw(IOSText.footnote, color: .cwMuted).padding(.leading, 16).padding(.bottom, 7) }
            CwCard(h: 16, v: 3) {
                VStack(spacing: 0) {
                    Group(subviews: content()) { subviews in
                        ForEach(Array(subviews.enumerated()), id: \.element.id) { index, subview in
                            if index > 0 {
                                Rectangle().fill(Color.cwStroke).frame(height: hairline).padding(.leading, subview.containerValues.dividerInset)
                            }
                            subview
                        }
                    }
                }
            }
            if let footer {
                Text(footer).cw(IOSText.footnote, color: .cwMuted).lineSpacing(3).padding(.horizontal, 16).padding(.top, 7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum FormMetrics {
    static let textInset: CGFloat = 44
    static let minHeight: CGFloat = 50
}

/// A settings row: coloured icon tile, label, trailing value, chevron.
struct FormRow<Trailing: View>: View {
    var icon: String?
    let label: String
    var destructive = false
    var chevron = false
    var onTap: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(icon: String? = nil, label: String, destructive: Bool = false, chevron: Bool = false, onTap: (() -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon; self.label = label; self.destructive = destructive; self.chevron = chevron; self.onTap = onTap; self.trailing = trailing
    }

    var body: some View {
        let hasTrailing = !(Trailing.self == EmptyView.self)
        let color: Color = destructive ? .cwOver : (onTap != nil && !hasTrailing && !chevron ? .cwAccent : .cwInk)
        let row = HStack(spacing: 0) {
            if let icon {
                FormIconTile(icon, color: destructive ? Color(hex: 0xFF383C) : nil)
                Spacer().frame(width: FormMetrics.textInset - FormIconTile.size)
            }
            Text(label).cw(IOSText.body, color: color).frame(maxWidth: .infinity, alignment: .leading)
            trailing().font(.cw(IOSText.body)).foregroundStyle(Color.cwMuted).lineLimit(1)
            if chevron { LIcon("chevron-right", size: 14, color: .cwMuted.opacity(0.6)).padding(.leading, 8) }
        }
        .frame(minHeight: FormMetrics.minHeight)
        Group {
            if let onTap { Pressable(onTap: onTap) { row } } else { row }
        }
        .containerValue(\.dividerInset, icon != nil ? FormMetrics.textInset : 0)
    }
}

extension FormRow where Trailing == EmptyView {
    init(icon: String? = nil, label: String, destructive: Bool = false, chevron: Bool = false, onTap: (() -> Void)? = nil) {
        self.init(icon: icon, label: label, destructive: destructive, chevron: chevron, onTap: onTap) { EmptyView() }
    }
}

/// iOS Settings-style coloured icon tile with a white glyph.
struct FormIconTile: View {
    static let size: CGFloat = 29
    let icon: String
    var color: Color?

    init(_ icon: String, color: Color? = nil) { self.icon = icon; self.color = color }

    private static let orange = Color(hex: 0xFF8D28), green = Color(hex: 0x34C759), red = Color(hex: 0xFF383C),
        purple = Color(hex: 0xCB30E0), pink = Color(hex: 0xFF2D55), yellow = Color(hex: 0xFFCC00), brown = Color(hex: 0xAC7F5E),
        gray = Color(hex: 0x8E8E93), black = Color(hex: 0x1C1C1E)

    private static let colors: [String: Color] = [
        "book-open": orange, "check": green, "receipt": gray, "banknote": green, "coins": green, "cloud-off": gray, "cloud": gray,
        "cloud-check": green, "upload": orange, "download": purple, "info": gray, "layout-grid": purple, "sun-moon": black,
        "languages": gray, "refresh-cw": gray, "credit-card": orange, "wallet": orange, "piggy-bank": pink, "archive": brown,
        "equal": gray, "trash": red, "log-out": red, "chart-pie": purple, "folder-search": yellow, "shield-check": green,
        "circle-user-round": gray,
    ]

    private static let symbols: [String: String] = [
        "book-open": "book.fill", "receipt": "doc.text.fill", "cloud": "icloud.fill", "cloud-off": "icloud.slash.fill",
        "cloud-check": "checkmark.icloud.fill", "upload": "square.and.arrow.up.fill", "download": "square.and.arrow.down.fill",
        "info": "info.circle.fill", "layout-grid": "square.grid.2x2.fill", "sun-moon": "circle.lefthalf.filled", "languages": "globe",
        "refresh-cw": "arrow.clockwise", "credit-card": "creditcard.fill", "wallet": "creditcard.fill", "piggy-bank": "banknote.fill",
        "archive": "archivebox.fill", "equal": "equal", "trash": "trash.fill", "log-out": "rectangle.portrait.and.arrow.right",
        "chart-pie": "chart.pie.fill", "folder-search": "folder.fill", "shield-check": "checkmark.shield.fill",
        "circle-user-round": "person.crop.circle.fill", "check": "checkmark",
    ]

    private static let coinsGlyph = #"<circle cx="15.2" cy="15.2" r="6.8" fill="{fg}"/><circle cx="9.4" cy="9.4" r="8.3" fill="{bg}"/><circle cx="9.4" cy="9.4" r="7" fill="{fg}"/><circle cx="9.4" cy="9.4" r="4.4" fill="none" stroke="{bg}" stroke-width="1.2"/>"#

    var body: some View {
        let base = color ?? Self.colors[icon] ?? Self.gray
        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
            .fill(LinearGradient(colors: [base.mix(with: .white, by: 0.12), base], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.22), location: 0), .init(color: .white.opacity(0), location: 0.35)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .frame(width: Self.size, height: Self.size)
            .overlay { glyph(base) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(_ base: Color) -> some View {
        if icon == "banknote" {
            Text("¥").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
        } else if icon == "coins" {
            SVGGlyphView(glyph: SVGGlyph.parse(Self.coinsGlyph, defaultFill: .none, defaultStroke: .none), color: .white,
                         tokens: ["{fg}": .white, "{bg}": base.mix(with: .white, by: 0.06)])
                .frame(width: 21, height: 21)
        } else if let symbol = Self.symbols[icon] {
            Image(systemName: symbol).font(.system(size: 16, weight: icon == "check" ? .bold : .medium)).foregroundStyle(.white)
        } else {
            LIcon(icon, size: 19, color: .white, strokeWidth: 2.3)
        }
    }
}

/// A plain text field in the app's body style.
struct FormTextField: View {
    @Binding var text: String
    let hint: String
    var keyboard: UIKeyboardType = .default
    var alignment: TextAlignment = .leading
    var focus: FocusState<Bool>.Binding?
    var axis: Axis = .horizontal

    var body: some View {
        let field = TextField("", text: $text, prompt: Text(hint).foregroundStyle(Color.cwMuted), axis: axis)
            .font(.cw(IOSText.body))
            .foregroundStyle(Color.cwInk)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .multilineTextAlignment(alignment)
            .padding(.vertical, 12)
        if let focus { field.focused(focus) } else { field }
    }
}

/// A row with an icon tile, a label and a text field on the right; an error line underneath.
struct LabeledField: View {
    let icon: String
    let label: String
    @Binding var text: String
    var hint = ""
    var keyboard: UIKeyboardType = .default
    var error: String?
    var alignEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                FormIconTile(icon)
                Spacer().frame(width: FormMetrics.textInset - FormIconTile.size)
                Text(label).cw(IOSText.body)
                Spacer().frame(width: 12)
                FormTextField(text: $text, hint: hint, keyboard: keyboard, alignment: alignEnd ? .trailing : .leading)
            }
            .frame(minHeight: FormMetrics.minHeight)
            if let error {
                Text(error).cw(IOSText.footnote, color: .cwOver).padding(.leading, FormMetrics.textInset).padding(.bottom, 10)
            }
        }
        .containerValue(\.dividerInset, FormMetrics.textInset)
    }
}

/// Keeps typed money tidy: digits, one dot, two decimals, at most 10 integer digits.
func sanitizeMoneyInput(_ text: String, signed: Bool = false) -> String? {
    let cleaned = text.replacingOccurrences(of: "。", with: ".").replacingOccurrences(of: "．", with: ".").replacingOccurrences(of: ",", with: "")
    let pattern = signed ? #"^-?\d{0,10}(\.\d{0,2})?$"# : #"^\d{0,10}(\.\d{0,2})?$"#
    return cleaned.range(of: pattern, options: .regularExpression) != nil ? cleaned : nil
}

/// Large bold title at the top of a list inside a sheet (设置与备份).
struct SheetLargeTitle: View {
    let title: String
    var body: some View { Text(title).cw(30, .bold).lineLimit(1).padding(.horizontal, 4).padding(.bottom, 22) }
}


// MARK: Drag down to close (记一笔 / 订阅)

struct SheetDrag {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
}

private struct SheetDragKey: EnvironmentKey { static let defaultValue: SheetDrag? = nil }
extension EnvironmentValues {
    var sheetDrag: SheetDrag? {
        get { self[SheetDragKey.self] }
        set { self[SheetDragKey.self] = newValue }
    }
}

/// The whole sheet follows a downward drag on its handles (the bottom bar) and closes once pulled
/// far enough — a third of its height, or a fast flick of at least 140 pt. A shorter pull springs
/// back. Pulling the scrolled content down past its top by 120 pt also closes. `onClose` returns
/// true when the sheet will really close (false when it asks to discard changes first).
struct DragToCloseSheet: ViewModifier {
    let onClose: () -> Bool
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        GeometryReader { geo in
            content
                .background(Color.cwSheet.ignoresSafeArea(edges: .bottom))
                // Rounded top while it moves; the mask runs past the bottom so the home-indicator strip stays filled.
                .mask(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                        .frame(height: geo.size.height + 400)
                }
                .offset(y: offset)
                .environment(\.sheetDrag, SheetDrag(changed: { dy in
                    offset = dy > 0 ? dy : dy / 6
                }, ended: { dy, predicted in
                    let close = dy > geo.size.height / 3 || (predicted - dy > 400 && dy > 140) || dy < -1000
                    if close && onClose() {
                        withAnimation(.easeIn(duration: 0.22)) { offset = geo.size.height + 60 }
                    } else {
                        withAnimation(IOSMotion.snappy) { offset = 0 }
                    }
                }))
        }
        .interactiveDismissDisabled(true)
    }
}

private struct SheetDragHandle: ViewModifier {
    @Environment(\.sheetDrag) private var drag
    @State private var tracking: Bool?

    func body(content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { v in
                if tracking == nil { tracking = abs(v.translation.height) > abs(v.translation.width) }
                if tracking == true { drag?.changed(v.translation.height) }
            }
            .onEnded { v in
                if tracking == true { drag?.ended(v.translation.height, v.predictedEndTranslation.height) }
                tracking = nil
            })
    }
}

private struct ScrollPullToClose: ViewModifier {
    @Environment(\.sheetDrag) private var drag
    @State private var overscroll: CGFloat = 0
    @State private var interacting = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, pull in
                overscroll = pull
            }
            .onScrollPhaseChange { old, phase in
                if old == .interacting && phase != .interacting && overscroll > 120 {
                    drag?.ended(UIScreen.main.bounds.height, UIScreen.main.bounds.height)
                }
            }
    }
}

extension View {
    /// The sheet follows a drag on this view and closes when pulled far enough.
    func sheetDragHandle() -> some View { modifier(SheetDragHandle()) }
    /// On the sheet's ScrollView: a long pull down past the top closes the sheet.
    func scrollPullToClose() -> some View { modifier(ScrollPullToClose()) }
}


// MARK: Pull down to close, guarded (记一笔 / 订阅)

/// Keeps the sheet from closing on an ordinary pull: a long pull down (on the sheet, or past the top
/// of its list) calls `onAttempt`, which then closes it or asks to discard typed input first.
struct GuardedSheetDismiss: ViewModifier {
    let onAttempt: () -> Void
    @Environment(PanelCloseGuard.self) private var closeGuard: PanelCloseGuard?
    func body(content: Content) -> some View {
        content
            .onAppear { closeGuard?.onAttempt = onAttempt }
            .onDisappear { closeGuard?.onAttempt = nil }
    }
}

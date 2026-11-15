import SwiftUI

/// Top-level pages, shown as pill tabs under the brand title.
enum CentwisePage: Int, CaseIterable, Identifiable, Hashable {
    case dashboard, subscriptions, transactions, categories
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: tr("概览", ctx: "tab")
        case .subscriptions: tr("订阅", ctx: "tab")
        case .categories: tr("分类", ctx: "tab")
        case .transactions: tr("账单", ctx: "tab")
        }
    }
}

struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @State private var scrolledPage: CentwisePage? = .dashboard
    @State private var page: CentwisePage = .dashboard
    @State private var position: Double = 0
    @State private var interacting = false
    @State private var pulledSettings = false
    @State private var showSettings = false
    @State private var newEntry = false
    @State private var subscriptionEditing: SubscriptionRequest?
    @State private var searchRequest = false
    @State private var launched = false
    @State private var devChooser = false

    var body: some View {
        ZStack(alignment: .bottom) {
            pages
            UndoDeleteToast()
                .padding(.horizontal, 18)
                .padding(.bottom, 80)
            // ＋ floats above everything and can be dragged anywhere; its spot is remembered.
            DraggableAddButton(label: page == .subscriptions ? tr("新增订阅") : tr("记一笔"),
                               onTap: store.loadingFailed ? nil : {
                                   if page == .subscriptions { subscriptionEditing = SubscriptionRequest() } else { openNewEntry() }
                               })
        }
        .background(Color.cwCanvas.ignoresSafeArea())
        .modifier(StoreOverlays(depth: 0))
        .cwSheet(isPresented: $showSettings) { SettingsSheet() }
        .cwSheet(isPresented: $newEntry) { EntryEditor() }
        .cwSheet(item: $subscriptionEditing) { SubscriptionEditor(subscription: $0.subscription) }
        .cwSheet(isPresented: $devChooser) { CategoryChooser(kind: .expense, selectedID: "", onPick: { _ in }) }
        .onAppear(perform: launch)
    }

    private func launch() {
        guard !launched else { return }
        launched = true
        PresentationTracker.shared.top = 0
        store.scanImportFolder()
        // Launch arguments for screenshots during development: -CWTab, -CWPeriod, -CWSheet.
        let defaults = UserDefaults.standard
        if let tab = defaults.string(forKey: "CWTab"), let p = ["dashboard": CentwisePage.dashboard, "subscriptions": .subscriptions,
                                                                  "categories": .categories, "transactions": .transactions][tab] {
            page = p; scrolledPage = p; position = Double(p.rawValue)
        }
        if let period = defaults.string(forKey: "CWPeriod"), let p = Period(rawValue: period) { store.period = p }
        switch defaults.string(forKey: "CWSheet") {
        case "settings": showSettings = true
        case "entry": newEntry = true
        case "subscription": subscriptionEditing = SubscriptionRequest()
        case "chooser": devChooser = true
        default: break
        }
    }

    private func go(_ next: CentwisePage) {
        if next != page { Haptics.selection() }
        page = next
        withAnimation(IOSMotion.smooth) { scrolledPage = next }
    }

    private func openNewEntry() {
        guard !store.loadingFailed else { return }
        newEntry = true
    }

    private var pages: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(CentwisePage.allCases) { p in
                    pageView(p)
                        .containerRelativeFrame(.horizontal)
                        .id(p)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledPage)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Double.self) { geo in
            geo.contentOffset.x / max(geo.containerSize.width, 1)
        } action: { _, value in
            position = value
            // Pulling past 概览's left edge opens 设置 (once per drag).
            if interacting && !pulledSettings && value * 1 < 0 {
                if let width = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen.bounds.width,
                   value * width < -56 {
                    pulledSettings = true
                    Haptics.selection()
                    showSettings = true
                }
            }
        }
        .onScrollPhaseChange { _, phase in
            interacting = phase == .interacting
            if phase == .idle { pulledSettings = false }
        }
        .onChange(of: scrolledPage) { _, now in
            if let now, now != page { page = now }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
    }

    @ViewBuilder
    private func pageView(_ p: CentwisePage) -> some View {
        switch p {
        case .dashboard: DashboardPage(onShowTransactions: { go(.transactions) }, onNewEntry: openNewEntry)
        case .subscriptions: SubscriptionsPage(editing: $subscriptionEditing)
        case .categories: CategoriesPage()
        case .transactions: TransactionsPage(searchRequest: $searchRequest)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            if store.isDemo || store.loadingFailed {
                Text(store.isDemo ? tr("预览模式 · 初始为演示数据 · 退出后不保存修改") : tr("账本读取失败 · 原文件已保留 · 写入已暂停"))
                    .cw(12, .medium, color: .cwMuted)
                    .frame(maxWidth: .infinity).frame(height: 26)
                    .background(Color.cwTrack)
            }
            HStack(spacing: 0) {
                headerButton("cog", tr("设置与备份"), size: 24) { showSettings = true }
                Text("Centwise").font(.cw(22, .heavy, brand: true)).foregroundStyle(Color.cwInk)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                headerButton("search", tr("搜索账单"), size: 22) {
                    searchRequest = true
                    go(.transactions)
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
            tabs.frame(height: 46)
        }
        // Frosted header, iOS Settings style: plain canvas at rest; pages scrolling behind it show
        // through blurred and washed. A soft wash continues 30 pt below the tabs.
        .background {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.cwCanvas.opacity(0.62)).ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [Color.cwCanvas.opacity(0.5), Color.cwCanvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 30).offset(y: 30).allowsHitTesting(false)
        }
    }

    private func headerButton(_ icon: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Pressable(onTap: action) {
            LucideIcon(name: icon, size: size, color: Color.cwInk.opacity(0.8), strokeWidth: 1.75).frame(width: 40, height: 40)
        }
        .accessibilityLabel(label)
    }

    private var tabs: some View {
        // Centred like the Flutter header; scrolls only if the labels ever outgrow the width.
        ViewThatFits(in: .horizontal) {
            tabTrack.frame(maxWidth: .infinity)
            ScrollView(.horizontal) { tabTrack }.scrollIndicators(.hidden)
        }
    }

    private var tabTrack: some View {
        PillTrack(count: CentwisePage.allCases.count, position: position, spacing: 6, fill: Color.cwBrand) { i, t in
            let p = CentwisePage.allCases[i]
            Pressable(onTap: { go(p) }) {
                Text(p.title)
                    .cw(15, .semibold, color: Color.cwMuted.mix(with: .cwOnBrand, by: t))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
            }
            .accessibilityAddTraits(p == page ? .isSelected : [])
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: Bottom controls

    private var bottomControls: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 52, height: 1)
            Group {
                if page != .subscriptions {
                    PeriodCapsule().fixedSize()
                } else {
                    Color.clear.frame(height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            // Room for the ＋ at its default spot, so the capsule stays centred.
            Color.clear.frame(width: 52, height: 52)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}


/// The floating ＋: blue-tinted Liquid Glass with a white plus, so it stands apart from the black buttons
/// in the cards behind it. Tap to add; drag to move it anywhere on screen (it is kept clear of the
/// header and the screen edges, and its spot is remembered as a fraction of the free area).
struct DraggableAddButton: View {
    let label: String
    var onTap: (() -> Void)?

    private static let size: CGFloat = 52
    private static let key = "addButtonPosition"
    @State private var fraction: CGPoint? = DraggableAddButton.load()
    @State private var drag: CGSize = .zero
    @State private var dragging = false
    @State private var pressed = false

    private static func load() -> CGPoint? {
        guard let a = UserDefaults.standard.array(forKey: key) as? [Double], a.count == 2 else { return nil }
        return CGPoint(x: min(max(a[0], 0), 1), y: min(max(a[1], 0), 1))
    }

    /// The area the button's centre may occupy.
    private static func area(_ size: CGSize) -> CGRect {
        let r = Self.size / 2
        let minX = 16 + r, maxX = size.width - 16 - r
        let minY: CGFloat = 120 + r            // below the title and tabs
        let maxY = size.height - 8 - r         // the default bottom row
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    var body: some View {
        GeometryReader { geo in
            let area = Self.area(geo.size)
            let f = fraction ?? CGPoint(x: 1, y: 1)
            let base = CGPoint(x: area.minX + f.x * area.width, y: area.minY + f.y * area.height)
            let x = min(max(base.x + drag.width, area.minX), area.maxX)
            let y = min(max(base.y + drag.height, area.minY), area.maxY)
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.size, height: Self.size)
                // iOS system blue as tinted Liquid Glass.
                .glassEffect(.regular.tint(Color(lightHex: 0x007AFF, darkHex: 0x0A84FF)).interactive(), in: .circle)
                .shadow(color: .black.opacity(dragging ? 0.22 : 0.12), radius: dragging ? 14 : 8, y: dragging ? 8 : 4)
                .scaleEffect(dragging ? 1.12 : (pressed ? 0.9 : 1))
                .animation(.spring(duration: 0.3, bounce: 0.35), value: dragging)
                .animation(pressed ? .spring(duration: 0.2, bounce: 0) : .spring(duration: 0.45, bounce: 0.4), value: pressed)
                .contentShape(Circle())
                .position(x: x, y: y)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let moved = abs(v.translation.width) > 6 || abs(v.translation.height) > 6
                        if moved && !dragging { dragging = true; pressed = false; Haptics.medium() }
                        if dragging { drag = v.translation } else if !pressed { pressed = true }
                    }
                    .onEnded { v in
                        if dragging {
                            let nx = min(max(base.x + v.translation.width, area.minX), area.maxX)
                            let ny = min(max(base.y + v.translation.height, area.minY), area.maxY)
                            let next = CGPoint(x: (nx - area.minX) / area.width, y: (ny - area.minY) / area.height)
                            var t = Transaction(); t.disablesAnimations = true
                            withTransaction(t) { fraction = next; drag = .zero }
                            dragging = false
                            UserDefaults.standard.set([Double(next.x), Double(next.y)], forKey: Self.key)
                        } else {
                            pressed = false
                            onTap?()
                        }
                    })
                .opacity(onTap == nil ? 0.45 : 1)
                .accessibilityElement()
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onTap?() }
        }
    }
}

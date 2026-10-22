import SwiftUI
#if SWIFT_PACKAGE
import LedgerCore
#endif

/// Centwise visual language, modelled on Copilot Money (iOS):
/// a royal-blue header that fades into a cool off-white canvas, white rounded
/// cards with soft shadows, navy rounded typography, colour-coded categories
/// and green / orange / red budget status.
enum Theme {
    // Brand
    static let brand = adaptive(light: (0.16, 0.42, 0.89), dark: (0.13, 0.33, 0.78))
    static let brandDeep = adaptive(light: (0.09, 0.30, 0.78), dark: (0.06, 0.16, 0.42))
    static let accent = adaptive(light: (0.16, 0.42, 0.89), dark: (0.45, 0.66, 1.00))

    // Surfaces & text
    static let canvas = adaptive(light: (0.955, 0.964, 0.985), dark: (0.035, 0.065, 0.13))
    static let card = adaptive(light: (1.00, 1.00, 1.00), dark: (0.075, 0.12, 0.21))
    static let cardStroke = adaptive(light: (0.90, 0.92, 0.96), dark: (0.15, 0.22, 0.36))
    static let ink = adaptive(light: (0.10, 0.14, 0.29), dark: (0.93, 0.95, 1.00))
    static let muted = adaptive(light: (0.46, 0.51, 0.62), dark: (0.58, 0.64, 0.76))
    static let track = adaptive(light: (0.89, 0.91, 0.95), dark: (0.17, 0.23, 0.35))

    // Status
    static let income = adaptive(light: (0.15, 0.60, 0.27), dark: (0.36, 0.84, 0.46))
    static let expense = ink
    static let under = adaptive(light: (0.25, 0.70, 0.30), dark: (0.36, 0.84, 0.46))
    static let warning = adaptive(light: (0.95, 0.60, 0.16), dark: (1.00, 0.68, 0.28))
    static let over = adaptive(light: (0.86, 0.20, 0.20), dark: (1.00, 0.38, 0.36))

    // Kept for older call sites.
    static var heroText: Color { ink }
    static var sky: Color { brand }
    static var mint: Color { under }
    static var pink: Color { over }

    /// Copilot-style top wash: saturated blue under the title, fading into the canvas.
    static var headerGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: brandDeep, location: 0),
            .init(color: brand, location: 0.45),
            .init(color: canvas, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [brandDeep, brand], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var actionGradient: LinearGradient {
        LinearGradient(colors: [brand, brand], startPoint: .leading, endPoint: .trailing)
    }
    static var canvasGradient: LinearGradient {
        LinearGradient(colors: [canvas, canvas], startPoint: .top, endPoint: .bottom)
    }

    static func color(_ kind: EntryKind) -> Color {
        switch kind { case .income: income; case .expense: ink; case .transfer: accent; case .adjustment: muted }
    }

    /// Budget bar colour: green while comfortably under, orange near the limit, red when over.
    static func budgetColor(_ ratio: Double) -> Color {
        if ratio >= 1 { return over }
        if ratio >= 0.8 { return warning }
        return under
    }

    /// Categories carry no stored colour, so derive a stable one from the id.
    /// (String.hashValue is randomised per launch and must not be used here.)
    static func tint(for categoryID: String) -> Color {
        let seed = categoryID.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return palette[seed % palette.count]
    }
    static let palette: [Color] = [
        Color(red: 0.55, green: 0.27, blue: 0.93), // purple
        Color(red: 0.95, green: 0.47, blue: 0.13), // orange
        Color(red: 0.86, green: 0.22, blue: 0.27), // red
        Color(red: 0.10, green: 0.62, blue: 0.62), // teal
        Color(red: 0.22, green: 0.62, blue: 0.27), // green
        Color(red: 0.18, green: 0.45, blue: 0.92), // blue
        Color(red: 0.90, green: 0.25, blue: 0.58), // pink
        Color(red: 0.80, green: 0.60, blue: 0.08), // amber
        Color(red: 0.36, green: 0.36, blue: 0.86)  // indigo
    ]

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #endif
    }
}

extension Binding where Value == String {
    // Normalize only decimal-point variants produced by Chinese input methods.
    // Commas, grouping separators and arbitrary text still fail Money.parse.
    var moneyInput: Binding<String> {
        Binding(get: { wrappedValue }, set: { value in
            wrappedValue = value.replacingOccurrences(of: "。", with: ".")
                .replacingOccurrences(of: "．", with: ".")
        })
    }
}

extension View {
    /// White rounded card with a hairline border, no shadow.
    func ledgerCard(padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke, lineWidth: 0.75) }
    }
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func moneyKeyboard() -> some View {
        #if os(iOS)
        // On this iOS 27.2 beta device, decimalPad input-mode setup aborts
        // while mirroring. Keep a system keyboard, but avoid that number-pad path.
        keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
        #else
        self
        #endif
    }
    @ViewBuilder func signedMoneyKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
        #else
        self
        #endif
    }
    @ViewBuilder func editorFrame(minHeight: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: 380, minHeight: minHeight)
        #else
        self
        #endif
    }
    func ledgerFormBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.canvas)
    }
}

/// Amount with a small raised currency sign, e.g. ˢ¥2,413.00 — Copilot's signature number style.
struct AmountText: View {
    let cents: Int64
    var size: CGFloat = 16
    var weight: Font.Weight = .semibold
    /// nil = automatic ("−" for negative values); "" = never show a sign.
    var sign: String? = nil
    var body: some View {
        let prefix = sign ?? (cents < 0 ? "−" : "")
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            if !prefix.isEmpty { Text(prefix).font(.system(size: size, weight: weight, design: .rounded)) }
            Text("¥").font(.system(size: size * 0.56, weight: weight, design: .rounded)).baselineOffset(size * 0.36)
            Text(Money.text(abs(cents), symbol: false)).font(.system(size: size, weight: weight, design: .rounded))
                .monospacedDigit()
        }.lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(prefix + Money.text(abs(cents)))
    }
}

/// Small spaced caption used above every card, e.g. "待核对" / "近六个月".
struct CardCaption: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let trailing {
                if let action {
                    Button(action: action) {
                        HStack(spacing: 2) { Text(trailing); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)) }
                    }.buttonStyle(.plain).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.accent)
                } else {
                    Text(trailing).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

/// Kept for older call sites.
struct SectionLabel: View {
    let title: String
    var subtitle: String? = nil
    var body: some View { CardCaption(title: title, trailing: subtitle) }
}

/// Tinted capsule label for a category, like Copilot's "🍔 RESTAURANTS" tag.
struct CategoryPill: View {
    let name: String
    let symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(name).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
        }.padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}

/// Rounded budget bar with a coloured fill and a light track.
struct BudgetBar: View {
    let ratio: Double
    var height: CGFloat = 7
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.budgetColor(ratio))
                    .frame(width: max(ratio > 0 ? height : 0, proxy.size.width * min(1, max(0, ratio))))
            }
        }.frame(height: height)
    }
}

/// Floating period selector: ‹ [今天 | 本月 | 近一年] ›. Arrows step a day, a month or 12 months
/// in the current mode; tapping the selected segment again jumps back to now.
struct MonthCapsule: View {
    @EnvironmentObject var store: LedgerStore
    var body: some View {
        HStack(spacing: 2) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 36)
            }.accessibilityLabel(stepLabel(-1))
            segment(.day, title: store.period == .day ? store.periodName : "今天")
            segment(.month, title: store.period == .month ? store.periodName : "本月")
            segment(.year, title: store.period == .year ? store.periodName : "近一年")
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 30, height: 36)
            }.accessibilityLabel(stepLabel(1))
        }.buttonStyle(.plain).foregroundStyle(Theme.ink)
            .padding(4)
            .background(Theme.card, in: Capsule())
            .overlay { Capsule().stroke(Theme.cardStroke.opacity(0.7), lineWidth: 0.5) }
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
    }
    private func segment(_ period: LedgerStore.Period, title: String) -> some View {
        let selected = store.period == period
        return Button { withAnimation(.easeInOut(duration: 0.2)) { store.select(period) } } label: {
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(selected ? Theme.ink : Theme.muted)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 11).frame(minWidth: 50).frame(height: 32)
                .background(selected ? Theme.accent.opacity(0.14) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }.accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(selected ? "再点一次回到当前" : "")
    }
    private func step(_ value: Int) {
        withAnimation(.easeInOut(duration: 0.2)) { store.stepPeriod(value) }
    }
    private func stepLabel(_ value: Int) -> String {
        switch store.period {
        case .day: value < 0 ? "前一天" : "后一天"
        case .month: value < 0 ? "上个月" : "下个月"
        case .year: value < 0 ? "前一年" : "后一年"
        }
    }
}

/// Kept for older call sites.
struct MonthPicker: View {
    var body: some View { MonthCapsule() }
}

/// Round floating action button (Copilot's "+" and sparkle buttons).
struct FloatingCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 52, height: 52)
                .background(Theme.card, in: Circle())
                .overlay { Circle().stroke(Theme.cardStroke.opacity(0.7), lineWidth: 0.5) }
                .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 6)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// Full-width bold action bar, like Copilot's "SAVE" bar.
struct PrimaryBarButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled
    init(tint: Color = Theme.accent) { self.tint = tint }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded)).tracking(0.6)
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.85))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? tint : Theme.muted.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Copilot transaction row: name · category pill · amount.
struct EntryRow: View {
    @EnvironmentObject var store: LedgerStore
    let entry: Entry
    var showDate = false
    var body: some View {
        HStack(spacing: 10) {
            if showDate {
                Text(entry.date.formatted(.dateTime.month(.defaultDigits).day()))
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                    .frame(width: 46, alignment: .leading)
            }
            if entry.kind == .transfer || entry.kind == .adjustment {
                Image(systemName: entry.kind.symbol).font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted).frame(width: 18, height: 18)
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(Theme.muted.opacity(0.7), lineWidth: 1) }
            }
            Text(title).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.ink).lineLimit(1)
            if entry.pending || entry.needsReview {
                Circle().fill(entry.needsReview ? Theme.over : Theme.warning).frame(width: 6, height: 6)
                    .accessibilityLabel(entry.needsReview ? "待核对" : "待入账")
            }
            Spacer(minLength: 6)
            if let category {
                CategoryPill(name: category.name, symbol: category.symbol, tint: Theme.tint(for: category.id))
            } else if entry.allocations.count > 1 {
                CategoryPill(name: "\(entry.allocations.count) 项分摊", symbol: "square.split.2x2", tint: Theme.muted)
            }
            AmountText(cents: entry.amount, size: 15, weight: .semibold, sign: sign)
                .foregroundStyle(amountColor)
                .frame(minWidth: 72, alignment: .trailing)
        }.padding(.vertical, 9).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
    private var category: LedgerCategory? {
        guard entry.allocations.count == 1, let id = entry.allocations.first?.categoryID else { return nil }
        return store.ledger.categories.first { $0.id == id }
    }
    private var title: String {
        if !entry.note.isEmpty { return entry.note }
        if !entry.payee.isEmpty { return entry.payee }
        if entry.kind == .transfer {
            let to = entry.destinationID.map { store.accountName($0) } ?? "—"
            return "\(store.accountName(entry.accountID)) → \(to)"
        }
        return store.categoryName(entry)
    }
    /// Expenses read as plain amounts (Copilot style); refunds and income are marked.
    private var sign: String {
        switch entry.kind {
        case .expense: entry.amount < 0 ? "+" : ""
        case .income: entry.amount < 0 ? "−" : "+"
        case .transfer: ""
        case .adjustment: entry.amount < 0 ? "−" : "+"
        }
    }
    private var amountColor: Color {
        if entry.kind == .income && entry.amount > 0 { return Theme.income }
        if entry.kind == .expense && entry.amount < 0 { return Theme.income }
        return entry.kind == .adjustment ? Theme.muted : Theme.ink
    }
}

/// Small grey day heading used in transaction lists ("10月13日 星期二" / "今天").
struct DayHeading: View {
    let date: Date
    var centered = false
    var body: some View {
        Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
    private var label: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month(.defaultDigits).day().weekday(.wide))
    }
}

/// Groups entries (already sorted newest first) by calendar day.
func groupedByDay(_ entries: [Entry]) -> [(day: Date, entries: [Entry])] {
    let calendar = Calendar.current
    var result: [(day: Date, entries: [Entry])] = []
    for entry in entries {
        let day = calendar.startOfDay(for: entry.date)
        if let last = result.last, last.day == day { result[result.count - 1].entries.append(entry) }
        else { result.append((day: day, entries: [entry])) }
    }
    return result
}

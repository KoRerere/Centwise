import SwiftUI
import AudioToolbox

/// The built-in calculator keypad of 记一笔 / 订阅:
///   + 1 2 3
///   − 4 5 6
///   × 7 8 9
///   ÷ . 0 ⌫
struct AmountKeypad: View {
    let text: String
    let onChanged: (String) -> Void
    var onLimit: (() -> Void)?
    @Environment(\.safeAreaInsets) private var safeArea

    static let operators: Set<String> = ["+", "−", "×", "÷"]

    /// Applies one key to the typed expression. Returns the text unchanged when the key isn't allowed.
    static func apply(_ text: String, _ key: String) -> String {
        if key == "delete" { return text.isEmpty ? text : String(text.dropLast()) }
        if operators.contains(key) {
            if text.isEmpty { return text }
            let last = String(text.last!)
            let base = operators.contains(last) || last == "." ? String(text.dropLast()) : text
            return base + key
        }
        let split = lastOperatorSplit(text)
        let operand = String(text.dropFirst(split))
        if key == "." {
            if operand.contains(".") { return text }
            return operand.isEmpty ? text + "0." : text + "."
        }
        if let dot = operand.firstIndex(of: ".") {
            return operand.distance(from: dot, to: operand.endIndex) - 1 >= 2 ? text : text + key
        }
        if operand.count >= 10 { return text }
        if operand == "0" { return String(text.prefix(split)) + key }
        return text + key
    }

    private static func lastOperatorSplit(_ text: String) -> Int {
        let chars = Array(text)
        var i = chars.count - 1
        while i >= 0 {
            if operators.contains(String(chars[i])) { return i + 1 }
            i -= 1
        }
        return 0
    }

    private static let rows: [[String]] = [["+", "1", "2", "3"], ["−", "4", "5", "6"], ["×", "7", "8", "9"], ["÷", ".", "0", "delete"]]

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 21) / 15
            VStack(spacing: 7) {
                ForEach(Self.rows, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(row, id: \.self) { value in key(value).frame(width: Self.operators.contains(value) ? unit * 3 : unit * 4) }
                    }
                }
            }
        }
        .frame(height: 48 * 4 + 7 * 3)
        .padding(.horizontal, 7)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color.cwTrack.opacity(0.9).ignoresSafeArea(edges: .bottom))
    }

    private func key(_ value: String) -> some View {
        let flat = value == "." || value == "delete"
        let op = Self.operators.contains(value)
        return KeypadKey(
            color: flat ? .clear : (op ? Color.cwInk.opacity(0.07) : .cwCard),
            pressedColor: flat || op ? Color.cwInk.opacity(0.16) : Color.cwCard.mix(with: .cwInk, by: 0.12),
            onPress: {
                let next = Self.apply(text, value)
                if next == text {
                    if value != "delete" && value != "." && !Self.operators.contains(value) {
                        Haptics.medium()
                        onLimit?()
                    }
                    return
                }
                onChanged(next)
            },
            onLongPress: value == "delete" ? { Haptics.medium(); onChanged("") } : nil
        ) {
            if value == "delete" {
                LIcon("delete", size: 22, color: .cwInk, strokeWidth: 1.75)
            } else {
                Text(value).cw(25)
            }
        }
        .accessibilityLabel(value == "delete" ? tr("删除，长按清空") : (value == "." ? tr("小数点") : value))
    }
}

/// One keypad key: acts on touch down (like the system keyboard), with a click and a light tap.
struct KeypadKey<Label: View>: View {
    let color: Color
    let pressedColor: Color
    let onPress: () -> Void
    var onLongPress: (() -> Void)?
    @ViewBuilder var label: () -> Label
    @State private var down = false
    @State private var longPressTask: Task<Void, Never>?

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(down ? pressedColor : color)
            .animation(down ? nil : .easeOut(duration: 0.18), value: down)
            .frame(height: 48)
            .overlay {
                label()
                    .scaleEffect(down ? 0.94 : 1)
                    .animation(down ? .easeOut(duration: 0.06) : IOSMotion.bouncy, value: down)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !down else { return }
                    down = true
                    Haptics.light()
                    AudioServicesPlaySystemSound(1104)
                    onPress()
                    if let onLongPress {
                        longPressTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            if !Task.isCancelled && down { onLongPress() }
                        }
                    }
                }
                .onEnded { _ in
                    down = false
                    longPressTask?.cancel()
                })
            .accessibilityAddTraits(.isButton)
    }
}

/// Blinking caret after the typed amount.
struct AmountCaret: View {
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 3, height: fontSize * 0.885)
                .opacity(visible ? 1 : 0)
        }
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first
        let i = window?.safeAreaInsets ?? .zero
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets { self[SafeAreaInsetsKey.self] }
}

/// Hardware keyboard on the amount (iPad keyboards, Mac, the simulator): digits, . + − × ÷, ⌫ and ⏎.
struct AmountHardwareKeys: ViewModifier {
    let enabled: Bool
    let text: String
    let onChanged: (String) -> Void
    var onLimit: (() -> Void)?
    var onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    private static let chars: [String: String] = [
        ".": ".", "。": ".", ",": ".", "+": "+", "-": "−", "−": "−", "*": "×", "x": "×", "X": "×", "×": "×", "/": "÷", "÷": "÷",
    ]

    func body(content: Content) -> some View {
        content
            .focusable(enabled)
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { if enabled { focused = true } }
            .onChange(of: enabled) { _, now in if now { focused = true } }
            .onKeyPress(phases: .down) { press in
                guard enabled else { return .ignored }
                if press.key == .delete || press.key == .deleteForward { apply("delete"); return .handled }
                if press.key == .return { onSubmit?(); return .handled }
                let c = press.characters
                if c.count == 1, let ch = c.first, ch.isASCII, ch.isNumber { apply(c); return .handled }
                if let mapped = Self.chars[c] { apply(mapped); return .handled }
                return .ignored
            }
    }

    private func apply(_ key: String) {
        let next = AmountKeypad.apply(text, key)
        if next == text {
            if key != "delete" && key != "." && !AmountKeypad.operators.contains(key) { onLimit?() }
            return
        }
        onChanged(next)
    }
}

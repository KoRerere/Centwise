import SwiftUI
import UIKit

/// Centwise visual language: monochrome iOS inset-grouped surfaces (Trackly 得意記 black-and-white
/// look). Colour only where it carries meaning: income green, over-budget red, category emoji and
/// chart slices. Every colour adapts to light / dark mode by itself.
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    init(lightHex: UInt32, darkHex: UInt32) {
        self.init(light: UIColor(hex: lightHex), dark: UIColor(hex: darkHex))
    }

    /// Near-black brand: buttons, selected states. White in dark mode.
    static let cwBrand = Color(lightHex: 0x0A0A0A, darkHex: 0xF5F5F5)
    /// Text / icons on top of cwBrand.
    static let cwOnBrand = Color(lightHex: 0xFFFFFF, darkHex: 0x0A0A0A)
    static let cwAccent = cwBrand
    /// systemGroupedBackground.
    static let cwCanvas = Color(lightHex: 0xF2F2F7, darkHex: 0x000000)
    static let cwCard = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)
    static let cwStroke = Color(lightHex: 0xD9D9DE, darkHex: 0x38383A)
    static let cwInk = Color(lightHex: 0x0A0A0A, darkHex: 0xF5F5F5)
    static let cwMuted = Color(lightHex: 0x8A8A8E, darkHex: 0x8D8D93)
    static let cwTrack = Color(lightHex: 0xE5E5EA, darkHex: 0x2C2C2E)
    static let cwIncome = Color(light: UIColor(red: 0.15, green: 0.60, blue: 0.27, alpha: 1), dark: UIColor(red: 0.36, green: 0.84, blue: 0.46, alpha: 1))
    static let cwUnder = Color(light: UIColor(red: 0.25, green: 0.70, blue: 0.30, alpha: 1), dark: UIColor(red: 0.36, green: 0.84, blue: 0.46, alpha: 1))
    static let cwWarning = Color(light: UIColor(red: 0.95, green: 0.60, blue: 0.16, alpha: 1), dark: UIColor(red: 1.00, green: 0.68, blue: 0.28, alpha: 1))
    static let cwOver = Color(light: UIColor(red: 0.86, green: 0.20, blue: 0.20, alpha: 1), dark: UIColor(red: 1.00, green: 0.38, blue: 0.36, alpha: 1))
    /// Floating light surfaces (search field, glass buttons): white / #1C1C1E.
    static let cwSurface = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)
    /// Raised secondary surface used for small cards in dark mode.
    static let cwRaised = Color(lightHex: 0xFFFFFF, darkHex: 0x2C2C2E)

    static func budget(_ ratio: Double) -> Color { ratio >= 1 ? .cwOver : (ratio >= 0.8 ? .cwWarning : .cwUnder) }

    static func kind(_ kind: EntryKind) -> Color {
        switch kind {
        case .income: .cwIncome
        case .expense: .cwInk
        case .transfer: .cwAccent
        case .adjustment: .cwMuted
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Apple's system colours (light values) without blue and red, for category chart slices.
let categoryPalette: [Color] = [
    Color(hex: 0xFF9500), Color(hex: 0x34C759), Color(hex: 0xAF52DE), Color(hex: 0xFF2D55), Color(hex: 0xFFCC00),
    Color(hex: 0x00C7BE), Color(hex: 0xA2845E), Color(hex: 0x8E8E93), Color(hex: 0x636366), Color(hex: 0xFF6482),
]

/// Categories carry no stored colour: a stable one derived from the id.
func categoryTint(_ id: String) -> Color {
    var seed = 0
    for unit in id.unicodeScalars { seed = (seed &* 31 &+ Int(unit.value)) & 0x7fffffff }
    return categoryPalette[seed % categoryPalette.count]
}

/// iOS text styles (Dynamic Type "Large" sizes).
enum IOSText {
    static let largeTitle: CGFloat = 34
    static let title1: CGFloat = 28
    static let title2: CGFloat = 22
    static let title3: CGFloat = 20
    static let headline: CGFloat = 17
    static let body: CGFloat = 17
    static let callout: CGFloat = 16
    static let subheadline: CGFloat = 15
    static let footnote: CGFloat = 13
    static let caption1: CGFloat = 12
    static let caption2: CGFloat = 11
}

extension Font {
    /// The app's text style: San Francisco (PingFang for Chinese) or, for the logo and money amounts,
    /// Nunito. Money gets tabular (equal-width) digits so amounts line up and don't jitter; other text
    /// keeps proportional digits, because tabular ones make "11月15日" look letter-spaced.
    /// `tabular` defaults to `brand`; pass true for a money amount set in the system font.
    static func cw(_ size: CGFloat, _ weight: Font.Weight = .regular, brand: Bool = false, tabular: Bool? = nil) -> Font {
        let font: Font
        if brand {
            let name: String
            switch weight {
            case .heavy, .black: name = "Nunito-ExtraBold"
            case .bold: name = "Nunito-Bold"
            case .semibold: name = "Nunito-SemiBold"
            case .medium: name = "Nunito-Medium"
            default: name = "Nunito-Regular"
            }
            font = .custom(name, fixedSize: size)
        } else {
            font = .system(size: size, weight: weight)
        }
        return tabular ?? brand ? font.monospacedDigit() : font
    }
}

extension View {
    /// Shorthand: `.cw(17, .semibold, color: .cwInk)`.
    func cw(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color? = nil, brand: Bool = false) -> some View {
        self.font(.cw(size, weight, brand: brand)).foregroundStyle(color ?? .cwInk)
    }
}

/// iOS motion: springs described by a perceptual duration and a bounce, like the system's.
enum IOSMotion {
    static let smooth = Animation.spring(duration: 0.5, bounce: 0)
    static let snappy = Animation.spring(duration: 0.5, bounce: 0.15)
    static let bouncy = Animation.spring(duration: 0.5, bounce: 0.3)
}

enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

/// One physical pixel. Separators drawn this thin land exactly on a pixel row, so every divider renders
/// the same; a 0.5 pt line (1.5 px on 3× screens) straddles pixels and looks lighter or darker by position.
var hairline: CGFloat {
    let scale = UITraitCollection.current.displayScale
    return 1 / (scale > 0 ? scale : 3)
}

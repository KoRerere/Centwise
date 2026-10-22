import SwiftUI

/// A Lucide line icon, drawn natively from `Lucide.paths` (see LucideIcons.swift).
///
/// Mirrors Lucide's own API: `size` defaults to 24 and `strokeWidth` to 2, and the
/// stroke scales with the size unless `absoluteStrokeWidth` is set. Colour comes
/// from the surrounding `foregroundStyle`, exactly like an SF Symbol:
///
///     LucideIcon(.wallet, size: 20).foregroundStyle(Theme.accent)
///     Label { Text("导出完整备份") } icon: { LucideIcon(.upload, size: 18) }
///
/// The size follows Dynamic Type (relative to `.body`). Icons are hidden from
/// VoiceOver unless an `accessibilityLabel` is passed, because most of them sit
/// next to text that already says what they mean.
struct LucideIcon: View {
    let icon: Lucide
    var strokeWidth: CGFloat
    var absoluteStrokeWidth: Bool
    var accessibilityLabel: Text?
    @ScaledMetric private var size: CGFloat

    init(_ icon: Lucide,
         size: CGFloat = 24,
         strokeWidth: CGFloat = 2,
         absoluteStrokeWidth: Bool = false,
         accessibilityLabel: Text? = nil) {
        self.icon = icon
        self.strokeWidth = strokeWidth
        self.absoluteStrokeWidth = absoluteStrokeWidth
        self.accessibilityLabel = accessibilityLabel
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        let paths = icon.paths
        let lineWidth = absoluteStrokeWidth ? strokeWidth : strokeWidth * size / 24
        let glyph = ZStack {
            LucideGridShape(gridPath: paths.fill).fill()
            LucideGridShape(gridPath: paths.stroke)
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)

        if let accessibilityLabel {
            glyph.accessibilityElement().accessibilityLabel(accessibilityLabel)
        } else {
            glyph.accessibilityHidden(true)
        }
    }
}

/// Scales a path drawn on Lucide's 24×24 grid into the frame it is given.
private struct LucideGridShape: Shape {
    let gridPath: Path

    func path(in rect: CGRect) -> Path {
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 24, y: rect.height / 24)
        return gridPath.applying(transform)
    }
}

import SwiftUI
import UIKit

/// Only one row is open at a time: opening one closes the others.
@Observable final class SwipeCoordinator {
    static let shared = SwipeCoordinator()
    var openID: String?
}

/// A horizontal pan that only starts on a leftward swipe (or any swipe while the row is open), so
/// vertical scrolling and page swipes elsewhere keep working.
struct LeftSwipePan: UIGestureRecognizerRepresentable {
    var allowRightward: Bool
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.allowRightward = allowRightward
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began: onBegan()
        case .changed: onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed: onEnded(recognizer.velocity(in: recognizer.view).x)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var allowRightward = false
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            guard abs(v.x) > abs(v.y) * 1.2 else { return false }
            return allowRightward || v.x < 0
        }
    }
}

/// Swipe left to reveal a red 删除 button (iOS Mail style, with a rubber band past it). Tapping it
/// turns the row into dust that blows away to the right, then the row collapses.
struct SwipeToDelete<Content: View>: View {
    let id: String
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    private static var gap: CGFloat { 12 }
    private static var buttonWidth: CGFloat { 76 }
    private static var actionWidth: CGFloat { gap + buttonWidth }
    private static var maxStretch: CGFloat { 36 }

    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat = 0
    @State private var rowFrame: CGRect = .zero
    @State private var dust: DustSnapshot?
    @State private var dustStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var coordinator: SwipeCoordinator { SwipeCoordinator.shared }

    private static func rubberBand(_ drag: CGFloat) -> CGFloat {
        let pull = -drag
        if pull <= actionWidth { return drag }
        let extra = pull - actionWidth
        return -(actionWidth + (1 - 1 / (extra * 0.55 / maxStretch + 1)) * maxStretch)
    }

    var body: some View {
        Group {
            if let dust, let dustStart {
                DustView(snapshot: dust, start: dustStart)
            } else {
                row
            }
        }
        .onChange(of: coordinator.openID) { _, open in
            if open != id && offset < -1 { withAnimation(IOSMotion.snappy) { offset = 0 } }
        }
    }

    private var row: some View {
        let reveal = -offset
        let squeeze = min(reveal, Self.actionWidth + Self.maxStretch)
        let slide = reveal - squeeze
        return ZStack(alignment: .trailing) {
            if reveal > 0 {
                Button(action: delete) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.cwOver)
                        .overlay {
                            if reveal > 60 {
                                VStack(spacing: 2) {
                                    LIcon("trash", size: 18, color: .white)
                                    Text(tr("删除")).cw(IOSText.footnote, .medium, color: .white)
                                }
                            }
                        }
                        .padding(.leading, min(Self.gap, reveal))
                        .frame(width: reveal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("删除"))
            }
            content()
                .background(GeometryReader { geo in Color.clear.onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in rowFrame = f } })
                .padding(.trailing, squeeze)
                .offset(x: -slide)
                .overlay {
                    if reveal > 0 {
                        Color.white.opacity(0.001).padding(.trailing, reveal)
                            .onTapGesture { close() }
                    }
                }
        }
        .clipped()
        .gesture(LeftSwipePan(allowRightward: offset < -1, onBegan: {
            dragStart = offset
        }, onChanged: { dx in
            let drag = max(-rowFrame.width, min(0, dragStart + dx))
            offset = Self.rubberBand(drag)
        }, onEnded: { velocity in
            if velocity < -300 || (velocity <= 300 && offset < -Self.actionWidth / 2) { open() } else { close() }
        }))
    }

    private func open() {
        withAnimation(IOSMotion.snappy) { offset = -Self.actionWidth }
        coordinator.openID = id
    }

    private func close() {
        withAnimation(IOSMotion.snappy) { offset = 0 }
        if coordinator.openID == id { coordinator.openID = nil }
    }

    private func delete() {
        Haptics.medium()
        if coordinator.openID == id { coordinator.openID = nil }
        offset = 0
        guard !reduceMotion else { withAnimation(.easeOut(duration: 0.22)) { onDelete() }; return }
        // Let the row settle back in place, then snapshot it from the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let snap = DustSnapshot.capture(rowFrame, seed: id.hashValue) {
                dust = snap
                dustStart = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onDelete()
                    dust = nil
                    dustStart = nil
                }
            } else {
                withAnimation(.easeOut(duration: 0.22)) { onDelete() }
            }
        }
    }
}

/// A screenshot of a row cut into 3-pt grains, each with its own delay, drift and spin.
struct DustSnapshot {
    struct Grain { let origin: CGPoint; let image: CGImage; let delay: Double; let drift: CGSize; let spin: Double }
    let size: CGSize
    let grains: [Grain]
    let scale: CGFloat
    static let grain: CGFloat = 3

    static func capture(_ frame: CGRect, seed: Int) -> DustSnapshot? {
        guard frame.width > 1, frame.height > 1,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)
        else { return nil }
        let scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: frame, format: { let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f }())
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: 0, y: 0)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        guard let cg = image.cgImage else { return nil }
        var rng = SeededRandom(seed: UInt64(bitPattern: Int64(seed)))
        let cols = Int(ceil(frame.width / grain)), rows = Int(ceil(frame.height / grain))
        var grains: [Grain] = []
        grains.reserveCapacity(cols * rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let rect = CGRect(x: CGFloat(c) * grain * scale, y: CGFloat(r) * grain * scale, width: grain * scale, height: grain * scale)
                guard let piece = cg.cropping(to: rect) else { continue }
                grains.append(Grain(origin: CGPoint(x: CGFloat(c) * grain, y: CGFloat(r) * grain), image: piece,
                                    delay: Double(c) / Double(cols) * 0.55 + rng.next() * 0.12,
                                    drift: CGSize(width: 18 + rng.next() * 46, height: -14 - rng.next() * 34),
                                    spin: (rng.next() - 0.5) * 3))
            }
        }
        return DustSnapshot(size: frame.size, grains: grains, scale: scale)
    }
}

struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

struct DustView: View {
    let snapshot: DustSnapshot
    let start: Date

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = min(1, timeline.date.timeIntervalSince(start) / 0.9)
            let collapse = easeInOut(min(1, max(0, (t - 0.7) / 0.3)))
            Canvas { context, _ in
                let progress = min(1, t / 0.75)
                let g = DustSnapshot.grain
                for grain in snapshot.grains {
                    let local = min(1, max(0, (progress - grain.delay) / 0.33))
                    if local >= 1 { continue }
                    let e = 1 - (1 - local) * (1 - local)
                    let alpha = 1 - local * local
                    if alpha <= 0.01 { continue }
                    var c = context
                    c.opacity = alpha
                    c.translateBy(x: grain.origin.x + g / 2 + grain.drift.width * e, y: grain.origin.y + g / 2 + grain.drift.height * e)
                    c.rotate(by: .radians(grain.spin * e))
                    c.scaleBy(x: 1 - 0.6 * e, y: 1 - 0.6 * e)
                    c.draw(Image(decorative: grain.image, scale: snapshot.scale), in: CGRect(x: -g / 2, y: -g / 2, width: g, height: g))
                }
            }
            .frame(width: snapshot.size.width, height: snapshot.size.height)
            .frame(height: snapshot.size.height * (1 - collapse), alignment: .top)
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

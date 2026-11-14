import Cocoa
import SwiftUI

// MARK: - Central Motion Physics Tokens

/// Single source of truth for every animation curve in AirIsland.
/// Every value is true spring physics (or an explicit cross-fade for content swaps),
/// so expand/collapse, hover depth, press feedback and layout re-flow all share
/// one organic, Apple-native feel instead of mixed linear / ease curves.
enum IslandMotion {
    /// Respect the system "Reduce Motion" accessibility preference.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func resolved(_ animation: Animation) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : animation
    }

    // MARK: Island morph

    /// Gentle, organic expand.
    static let expand = Animation.spring(response: 0.36, dampingFraction: 0.88, blendDuration: 0.10)
    /// Deliberately unhurried shrink (tuned slower at the user's request).
    static let collapse = Animation.spring(response: 0.64, dampingFraction: 0.92, blendDuration: 0.14)

    // MARK: Pointer depth

    /// Pointer entering a control: quick lift with a whisper of overshoot.
    static let hoverIn = Animation.spring(response: 0.30, dampingFraction: 0.78, blendDuration: 0.10)
    /// Pointer leaving: slightly longer settle so nothing snaps back.
    static let hoverOut = Animation.spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.12)

    // MARK: Weighted press

    /// mousedown -> depressed: immediate and heavy.
    static let press = Animation.spring(response: 0.20, dampingFraction: 0.62, blendDuration: 0.02)
    /// mouseup -> spring back with a weighted overshoot.
    static let release = Animation.spring(response: 0.34, dampingFraction: 0.64, blendDuration: 0.04)

    // MARK: Layout & content

    /// Frame / container interpolation when text, artwork or tabs remap.
    static let layout = Animation.spring(response: 0.38, dampingFraction: 0.88, blendDuration: 0.10)
    /// Small UI state changes (segmented pills, scrubber emphasis, nudge pills).
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.80, blendDuration: 0.06)
    /// Monotonic gauges (timer ring, stat bars): smooth, critically damped, no overshoot.
    static let progress = Animation.spring(response: 0.60, dampingFraction: 1.0, blendDuration: 0.10)
    /// Colour / material / album-theme morphs.
    static let theme = Animation.spring(response: 0.60, dampingFraction: 0.92, blendDuration: 0.12)
    /// Content cross-fade (text / artwork replacement). Critically damped so opacity
    /// never overshoots, but still true spring physics rather than an ease curve.
    static let fade = Animation.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.06)

    static func hover(_ hovering: Bool) -> Animation {
        resolved(hovering ? hoverIn : hoverOut)
    }

    static func pressedAnimation(_ isPressed: Bool) -> Animation {
        resolved(isPressed ? press : release)
    }
}

// MARK: - Fluid Text Remapping

/// Cross-fades swapped text (track title / artist / album) instead of snapping the
/// glyphs, while the surrounding stack interpolates its frame with the layout spring.
struct FluidTextSwap: View {
    let text: String
    var font: Font
    var color: Color = .primary
    var lineLimit: Int = 1
    var alignment: Alignment = .leading

    var body: some View {
        ZStack(alignment: alignment) {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .id(text)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 5)),
                        removal: .opacity
                    )
                )
        }
        .animation(IslandMotion.fade, value: text)
    }
}

// MARK: - Micro-Gesture Press

/// Adds the weighted press felt on every control to *any* surface — list rows, cards,
/// drag targets — without turning it into a Button. Pressing dips to `scale` on the
/// heavy press spring; releasing springs back with a weighted overshoot.
struct MicroPressModifier: ViewModifier {
    var scale: CGFloat = 0.97
    var isEnabled: Bool = true
    @State private var isPressed: Bool = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && isEnabled ? scale : 1.0)
            .animation(IslandMotion.pressedAnimation(isPressed), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled, !isPressed else { return }
                        isPressed = true
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                    }
            )
    }
}

extension View {
    func microPress(scale: CGFloat = 0.97, isEnabled: Bool = true) -> some View {
        modifier(MicroPressModifier(scale: scale, isEnabled: isEnabled))
    }
}

// MARK: - Cursor Tracking Sheen

/// Pointer position inside the island, normalised to 0…1 (top-left origin).
/// Kept as its own observable so a mouse move repaints *only* the tiny sheen view
/// instead of invalidating the whole island hierarchy — cheap enough for the 2017 MBA.
final class PointerGlow: ObservableObject {
    @Published private(set) var point: CGPoint = CGPoint(x: 0.62, y: 0.34)
    private var lastSent: CGPoint = CGPoint(x: -1, y: -1)

    func update(x: CGFloat, y: CGFloat) {
        guard x.isFinite, y.isFinite else { return }
        let clamped = CGPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
        // Ignore sub-1% jitter so we don't republish at the display's full polling rate
        guard abs(clamped.x - lastSent.x) > 0.01 || abs(clamped.y - lastSent.y) > 0.01 else { return }
        lastSent = clamped
        point = clamped
    }

    func reset(expanded: Bool) {
        let target = expanded ? CGPoint(x: 0.62, y: 0.34) : CGPoint(x: 0.70, y: 0.30)
        if lastSent != target {
            lastSent = target
            point = target
        }
    }
}

/// GPU-cheap specular highlight that trails the pointer with spring physics.
/// A single gradient-filled circle whose offset is animated — offset is interpolatable,
/// so the glide stays smooth even though the gradient itself never re-parameterises.
struct PointerSheenView: View {
    @ObservedObject var glow: PointerGlow
    var intensity: Double
    var spread: Double

    var body: some View {
        GeometryReader { geo in
            let diameter = max(geo.size.width, geo.size.height) * max(CGFloat(1.0), CGFloat(spread))
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(intensity),
                            Color.white.opacity(intensity * 0.32),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.5
                    )
                )
                .frame(width: diameter, height: diameter)
                .offset(
                    x: glow.point.x * geo.size.width - diameter * 0.5,
                    y: glow.point.y * geo.size.height - diameter * 0.5
                )
                .animation(IslandMotion.resolved(IslandMotion.hoverIn), value: glow.point)
        }
        .allowsHitTesting(false)
    }
}

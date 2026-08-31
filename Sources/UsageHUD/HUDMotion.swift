import SwiftUI

/// The app's motion vocabulary.
///
/// Every surface — notch tray, HUD window, badges, rings — pulls from this one
/// set of springs so the whole app moves like a single material instead of a
/// collection of views that each animate their own way.
enum HUDMotion {
    /// A surface opening as one motion: enough give to land with weight but no
    /// visible wobble.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// The tray unfurling: height and corner roll lead with visible overshoot —
    /// the drop forming.
    static let openHeight = Animation.spring(response: 0.4, dampingFraction: 0.64)
    /// Width spreads a beat behind the height on a heavier spring.
    static let openWidth = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Anything getting out of the way: crisp, near-critically damped.
    static let close = Animation.spring(response: 0.32, dampingFraction: 0.95)
    /// Content growing, moving, or swapping inside an open surface.
    static let detail = Animation.spring(response: 0.38, dampingFraction: 0.78)
    /// Hover focus: a quick lift with a hint of overshoot.
    static let focus = Animation.spring(response: 0.26, dampingFraction: 0.72)
    /// The peek swell: under-damped on the way in so it jiggles like a tapped
    /// droplet, crisp on the way out so leaving costs nothing.
    static let peekIn = Animation.spring(response: 0.34, dampingFraction: 0.6)
    static let peekOut = Animation.spring(response: 0.26, dampingFraction: 0.9)
    /// Data changing value: rings sweeping, bars filling, numbers counting.
    static let value = Animation.smooth(duration: 0.65)

    /// A slow breath for "live right now" indicators, phase 0...1. Driven by
    /// wall-clock time so it needs no view state and every pulsing element in
    /// the app inhales together.
    static func breath(_ date: Date, period: Double = 2.4) -> Double {
        let angle = date.timeIntervalSinceReferenceDate / period * 2 * .pi
        return (sin(angle) + 1) / 2
    }
}

/// Status colours shared across surfaces, matching `ProviderVisualStatus`.
enum HUDStatusPalette {
    /// Warnings that self-heal: stale caches, cooldowns. Never alarm-red.
    static let amber = Color(red: 1, green: 0.76, blue: 0.32)
}

/// The "streaming right now" chip: a breathing dot beside LIVE, inhaling on
/// the shared `HUDMotion.breath` clock with every other live indicator.
struct LiveBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let accent: Color
    var textScale: Double = 1

    var body: some View {
        if reduceMotion {
            content(breath: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                content(breath: HUDMotion.breath(context.date))
            }
        }
    }

    private func content(breath: Double) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(accent)
                .frame(width: 4, height: 4)
                .shadow(color: accent.opacity(0.3 + 0.5 * breath), radius: 1.5 + 2 * breath)
                .opacity(0.65 + 0.35 * breath)
            Text("LIVE")
                .font(.system(size: 7 * textScale, weight: .black, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(accent.opacity(0.9))
        }
        .accessibilityLabel("Live session active")
    }
}

// MARK: - Liquid transitions

/// Arriving content resolves out of a soft blur — condensation clearing —
/// which reads as material forming rather than an opacity pop.
private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    static func blurFade(radius: CGFloat) -> AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: radius),
            identity: BlurFadeModifier(radius: 0)
        )
    }

    /// Badges and notices condense in and evaporate out.
    static var statusBadge: AnyTransition {
        .scale(scale: 0.8)
            .combined(with: .opacity)
            .combined(with: .blurFade(radius: 3))
    }
}

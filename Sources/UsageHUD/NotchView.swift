import SwiftUI

/// Drives the tray animation from the pointer tracking in `NotchController`.
@MainActor
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    /// Collapsed size of the notch (or its stand-in) on the active display.
    @Published var notchSize = CGSize(width: NotchGeometry.virtualNotchWidth, height: NotchGeometry.fallbackMenuBarHeight)
    @Published var isHardwareNotch = false
}

/// The tray that grows out of the notch on hover.
///
/// Two stages: pointing at the notch drops a row of provider rings, and
/// hovering one grows that provider's detail inside the same shape rather than
/// floating a separate popover beside it.
struct NotchShelfView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var notch: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredIndex: Int?
    let openHUD: () -> Void

    var body: some View {
        let providers = visibleProviders
        let expanded = notch.isExpanded
        let detailIndex = expanded ? hoveredIndex.flatMap { $0 < providers.count ? $0 : nil } : nil
        let width = expanded
            ? NotchGeometry.expandedWidth(notch: notchMetrics, providerCount: providers.count)
            : notch.notchSize.width
        let detailHeight = detailIndex.map { index -> CGFloat in
            let hasWeekly = store.state(for: providers[index]).usage?.secondary != nil
            return NotchGeometry.detailHeight(windowCount: hasWeekly ? 2 : 1)
        } ?? 0
        let height = expanded
            ? notch.notchSize.height + NotchGeometry.trayHeight + detailHeight
            : notch.notchSize.height

        return ZStack(alignment: .top) {
            // The window stays at its largest size so only the shape animates.
            Color.clear

            shelf(width: width, height: height, expanded: expanded, providers: providers, detailIndex: detailIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded { hoveredIndex = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage HUD notch tray")
    }

    private var notchMetrics: NotchGeometry.Notch {
        NotchGeometry.Notch(
            rect: CGRect(origin: .zero, size: notch.notchSize),
            isHardware: notch.isHardwareNotch
        )
    }

    private func shelf(
        width: CGFloat,
        height: CGFloat,
        expanded: Bool,
        providers: [ProviderKind],
        detailIndex: Int?
    ) -> some View {
        let shape = NotchTrayShape(
            topRadius: expanded ? NotchGeometry.trayTopRadius : 0,
            bottomRadius: expanded ? NotchGeometry.trayBottomRadius : 0
        )
        return TraySurface(shape: shape, expanded: expanded)
            .overlay(
                // Barely-there rim: enough to hold an edge on a dark desktop,
                // not enough to outline the tray. NotchNook has none at all.
                shape.stroke(Color.white.opacity(expanded ? 0.05 : 0), lineWidth: 0.75)
            )
            .frame(width: width, height: height)
            // A collapsed tray would otherwise paint a black bar over the menu
            // bar on displays with no camera housing to hide behind.
            .opacity(expanded || notch.isHardwareNotch ? 1 : 0)
            .shadow(color: .black.opacity(expanded ? 0.6 : 0), radius: 22, y: 12)
            .overlay(alignment: .top) {
                if expanded {
                    VStack(spacing: 0) {
                        tray(providers)
                        if let detailIndex {
                            detail(providers[detailIndex])
                        }
                    }
                    .padding(.top, notch.notchSize.height)
                    .frame(width: width)
                    // The detail slides out from under the rings rather than
                    // spilling past the shape while it is still growing.
                    .clipped()
                }
            }
            .overlay(alignment: .top) {
                if !notch.isHardwareNotch && !expanded {
                    collapsedHint
                }
            }
    }

    private func tray(_ providers: [ProviderKind]) -> some View {
        HStack(spacing: NotchGeometry.tileSpacing) {
            ForEach(Array(providers.enumerated()), id: \.element) { item in
                tile(kind: item.element, index: item.offset)
            }
        }
        .padding(.top, NotchGeometry.trayTopPadding)
        .padding(.bottom, NotchGeometry.trayBottomPadding)
        .padding(.horizontal, NotchGeometry.trayHorizontalPadding)
    }

    private func tile(kind: ProviderKind, index: Int) -> some View {
        NotchProviderTile(
            kind: kind,
            state: store.state(for: kind),
            accent: Color(hudHex: settings.accentHex(for: kind)),
            isStale: store.isStale(for: kind),
            isHighlighted: hoveredIndex == index,
            isDimmed: hoveredIndex != nil && hoveredIndex != index,
            index: index,
            open: openHUD,
            hoverChanged: { hovering in
                if hovering {
                    hoveredIndex = index
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }
        )
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .top)
                    .combined(with: .opacity)
                    .combined(with: .offset(y: -14)),
                removal: .scale(scale: 0.82, anchor: .top).combined(with: .opacity)
            )
        )
        .transaction { transaction in
            guard !reduceMotion else {
                transaction.animation = nil
                return
            }
            // Rings cascade out of the notch left to right, but snap back
            // together on the way in — a staggered retract reads as lag.
            transaction.animation = notch.isExpanded
                ? .spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.055)
                : .spring(response: 0.24, dampingFraction: 0.9)
        }
    }

    private func detail(_ kind: ProviderKind) -> some View {
        NotchDetailSection(
            kind: kind,
            state: store.state(for: kind),
            accent: Color(hudHex: settings.accentHex(for: kind)),
            isStale: store.isStale(for: kind),
            notice: store.notice(for: kind)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Without a camera housing there is nothing on screen to hint at the hot
    /// zone, so leave a hairline of provider colour at the top edge.
    private var collapsedHint: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: visibleProviders.map { Color(hudHex: settings.accentHex(for: $0)) },
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: max(28, notch.notchSize.width * 0.32), height: 3)
            .opacity(0.55)
            .padding(.top, 1)
    }

    private var visibleProviders: [ProviderKind] {
        ProviderKind.allCases.filter { settings.isProviderVisible($0) }
    }
}

// MARK: - Ring

private struct NotchProviderTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ProviderKind
    let state: ProviderState
    let accent: Color
    let isStale: Bool
    let isHighlighted: Bool
    /// Another ring has focus, so this one steps back.
    let isDimmed: Bool
    let index: Int
    let open: () -> Void
    let hoverChanged: (Bool) -> Void
    @State private var hasAppeared = false

    private var remaining: Double? { state.usage?.primary.remainingPercent }

    var body: some View {
        VStack(spacing: NotchGeometry.ringToPercentGap) {
            ring
            percentLabel
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(isHighlighted && !reduceMotion ? 1.07 : 1)
        .opacity(isDimmed ? 0.55 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isHighlighted)
        .animation(.easeOut(duration: 0.18), value: isDimmed)
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .onTapGesture(perform: open)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            // The gauge fills itself in as it arrives, a beat behind the ring
            // it lives on, so the tray resolves rather than just appearing.
            withAnimation(.smooth(duration: 0.85).delay(0.1 + Double(index) * 0.055)) {
                hasAppeared = true
            }
        }
    }

    private var ring: some View {
        ZStack {
            // Ambient bloom in the provider's colour, so the tray is not just
            // grey discs on black.
            Circle()
                .fill(accent)
                .opacity(isHighlighted ? 0.26 : 0.12)
                .blur(radius: 12)
                .scaleEffect(1.08)

            // A solid disc, not a wash, so the arc reads crisply against it.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.205), Color(white: 0.115)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            Circle()
                .inset(by: 1.75)
                .trim(from: 0, to: hasAppeared ? (remaining ?? 0) / 100 : 0)
                .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.65), value: remaining ?? 0)

            ProviderGlyph(kind: kind)
                .foregroundStyle(Color.white.opacity(remaining == nil ? 0.4 : 0.97))
                .frame(width: NotchGeometry.ringDiameter * 0.44, height: NotchGeometry.ringDiameter * 0.44)

            if isStale {
                Circle()
                    .fill(Color(red: 1, green: 0.76, blue: 0.32))
                    .frame(width: 5, height: 5)
                    .offset(x: NotchGeometry.ringDiameter * 0.35, y: -NotchGeometry.ringDiameter * 0.35)
            }
        }
        .frame(width: NotchGeometry.ringDiameter, height: NotchGeometry.ringDiameter)
    }

    @ViewBuilder
    private var percentLabel: some View {
        if let remaining {
            Text("\(Int(remaining.rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(isHighlighted ? 1 : 0.88))
                .contentTransition(.numericText(value: remaining))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: remaining)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : -5)
        } else {
            Text(state.isFailed ? "ERR" : "—")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }

    private var accessibilityText: String {
        guard let remaining else { return "\(kind.displayName) usage unavailable" }
        return "\(kind.displayName), \(Int(remaining.rounded())) percent remaining"
    }
}

// MARK: - Detail, grown inside the tray

private struct NotchDetailSection: View {
    let kind: ProviderKind
    let state: ProviderState
    let accent: Color
    let isStale: Bool
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: NotchGeometry.detailSpacing) {
            // A hairline, not a border: the detail belongs to the tray, it is
            // not a card sitting on top of it.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, NotchGeometry.detailDividerInset)

            header
            switch state {
            case let .loaded(usage):
                window(usage.primary, title: "Current session")
                if let secondary = usage.secondary {
                    window(secondary, title: "All models")
                }
            case .loading:
                message("Checking limits…")
            case let .failed(text):
                message(text)
            }
        }
        .padding(.top, NotchGeometry.detailTopPadding)
        .padding(.bottom, NotchGeometry.detailBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            ProviderGlyph(kind: kind)
                .foregroundStyle(accent)
                .frame(width: 12, height: 12)
            Text(kind.displayName.capitalized)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            if isStale {
                Text("STALE")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.32))
            }
        }
        .frame(height: NotchGeometry.detailHeaderHeight)
        .padding(.horizontal, NotchGeometry.detailHorizontalPadding)
    }

    private func window(_ window: UsageWindow, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Spacer(minLength: 0)
                    Text("\(Int(window.remainingPercent.rounded()))% · \(resetText(window.resetsAt, now: context.date))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.13))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(4, geometry.size.width * window.remainingPercent / 100))
                        .shadow(color: accent.opacity(0.5), radius: 4)
                }
            }
            .frame(height: 4)
        }
        .frame(height: NotchGeometry.detailRowHeight, alignment: .top)
        .padding(.horizontal, NotchGeometry.detailHorizontalPadding)
    }

    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "no reset" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "resetting" }
        return "\(UsageFormatting.durationText(seconds)) left"
    }

    private func message(_ text: String) -> some View {
        Text(notice ?? text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(2)
            .frame(height: NotchGeometry.detailRowHeight, alignment: .top)
            .padding(.horizontal, NotchGeometry.detailHorizontalPadding)
    }
}

// MARK: - Surface

/// The tray's material.
///
/// Liquid Glass where the SDK and the OS both offer it, flat black otherwise —
/// the app still deploys to macOS 14, and CI currently builds against an SDK
/// with no glass API at all, so the gate has to be at compile time as well as
/// runtime.
///
/// Only the tray takes glass. The rings sitting on it stay solid: stacking
/// glass on glass muddies both, and the panel is the layer that should refract
/// what is behind it.
private struct TraySurface: View {
    /// How far the glass itself is pulled toward black.
    static let tintStrength: Double = 0.9
    /// `Glass.regular` keeps a floor of luminosity so its material stays
    /// legible, which tint alone cannot drive out. A scrim over the top takes
    /// it the rest of the way to the hardware notch's black, leaving the
    /// refracted edges and specular highlights showing through.
    static let scrimOpacity: Double = 0.42

    let shape: NotchTrayShape
    let expanded: Bool

    var body: some View {
#if canImport(FoundationModels) // proxy for "built against the macOS 26+ SDK"
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular.tint(Color.black.opacity(expanded ? Self.tintStrength : 1)),
                    in: shape
                )
                .overlay(shape.fill(Color.black.opacity(expanded ? Self.scrimOpacity : 1)))
        } else {
            shape.fill(Color.black)
        }
#else
        shape.fill(Color.black)
#endif
    }
}

// MARK: - Shell

/// The tray as it hangs off the screen edge.
///
/// The top corners flare *outward* into the bezel instead of stopping square,
/// so the black reads as carved out of the display — the same trick the
/// hardware notch plays where it meets the menu bar. The bottom corners round
/// the ordinary way, because that edge hangs free.
struct NotchTrayShape: Shape {
    /// Radius of the outward flare where the tray meets the screen edge.
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.height))
        let bottom = max(0, min(bottomRadius, min(rect.width, rect.height - top) / 2))

        var path = Path()
        // Start out on the bezel, left of the tray, and curve in and down. A
        // true quarter circle, so the join is tangent to the screen edge at
        // one end and to the tray's side at the other.
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.minX - top, y: rect.minY + top),
            radius: top,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addArc(
            center: CGPoint(x: rect.maxX + top, y: rect.minY + top),
            radius: top,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private extension ProviderState {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

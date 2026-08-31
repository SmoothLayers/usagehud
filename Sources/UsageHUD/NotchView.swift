import SwiftUI

/// Drives the tray animation from the pointer tracking in `NotchController`.
@MainActor
final class NotchState: ObservableObject {
    @Published var isExpanded = false
    /// Pointer is parked in the hot zone but the tray has not opened yet: the
    /// shape swells a little so the notch acknowledges the cursor.
    @Published var isPeeking = false
    /// Collapsed size of the notch (or its stand-in) on the active display.
    @Published var notchSize = CGSize(width: NotchGeometry.virtualNotchWidth, height: NotchGeometry.fallbackMenuBarHeight)
    @Published var isHardwareNotch = false
    /// Index of the tile the pointer is on, if any. Lives here rather than in
    /// view-local state so the controller and previews can read and drive it.
    @Published var hoveredIndex: Int?
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
    let openHUD: () -> Void

    var body: some View {
        let providers = visibleProviders
        let expanded = notch.isExpanded
        let peeking = notch.isPeeking && !expanded
        let detailIndex = expanded ? notch.hoveredIndex.flatMap { $0 < providers.count ? $0 : nil } : nil
        // The closed shape sits a touch wider than the camera housing so its
        // corner curves stay visible against the housing's own — the notch
        // reads as a soft object, not a cut-out, and the peek has curves to
        // grow from.
        let closedWidth = notch.notchSize.width
            + (notch.isHardwareNotch ? NotchGeometry.closedOverhang * 2 : 0)
            + (peeking ? NotchGeometry.peekWidthGrowth : 0)
        // One width for every open state: hovering swaps the tray's content
        // but never resizes the shape, so the silhouette is a constant.
        let width = expanded
            ? NotchGeometry.expandedWidth(notch: notchMetrics, providerCount: providers.count)
            : closedWidth
        let height = expanded
            ? notch.notchSize.height + NotchGeometry.trayHeight
            : notch.notchSize.height + (peeking ? NotchGeometry.peekHeightGrowth : 0)

        return ZStack(alignment: .top) {
            // The window stays at its largest size so only the shape animates.
            Color.clear

            shelf(width: width, height: height, expanded: expanded, peeking: peeking, providers: providers, detailIndex: detailIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded { notch.hoveredIndex = nil }
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
        peeking: Bool,
        providers: [ProviderKind],
        detailIndex: Int?
    ) -> some View {
        // The closed shape keeps small curves so opening grows them rather
        // than conjuring them: the notch always reads as the same soft object.
        let shape = NotchTrayShape(
            topRadius: expanded ? NotchGeometry.trayTopRadius : NotchGeometry.closedTopRadius,
            bottomRadius: expanded ? NotchGeometry.trayBottomRadius : NotchGeometry.closedBottomRadius
        )
        return TraySurface(shape: shape, expanded: expanded)
            .overlay(
                // Barely-there rim, brightest along the top flare where the
                // tray meets the screen edge — a specular catch that makes it
                // read as a physical object sliding out of the housing — with
                // a fainter glint along the free-hanging bottom lip.
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.11), location: 0),
                            .init(color: Color.white.opacity(0.02), location: 0.3),
                            .init(color: Color.white.opacity(0.015), location: 0.75),
                            .init(color: Color.white.opacity(0.07), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .opacity(expanded ? 1 : 0)
            )
            .frame(height: height)
            .animation(reduceMotion ? nil : (expanded ? HUDMotion.openHeight : HUDMotion.close), value: expanded)
            .frame(width: width)
            .animation(reduceMotion ? nil : (expanded ? HUDMotion.openWidth : HUDMotion.close), value: expanded)
            // A collapsed tray would otherwise paint a black bar over the menu
            // bar on displays with no camera housing to hide behind — unless
            // the pointer is already parked there, in which case the peek IS
            // the affordance the housing would have provided.
            .opacity(expanded || peeking || notch.isHardwareNotch ? 1 : 0)
            // The peek casts a whisper of the open tray's shadow, so the notch
            // visibly wakes before it moves.
            .shadow(
                color: .black.opacity(expanded ? 0.6 : (peeking ? 0.35 : 0)),
                radius: expanded ? 22 : 8,
                y: expanded ? 12 : 3
            )
            .overlay(alignment: .top) {
                if expanded {
                    tray(providers, detailIndex: detailIndex)
                        .padding(.top, notch.notchSize.height)
                        .frame(width: width)
                        // Swapping content stays inside the shape while the
                        // tray is still growing open.
                        .clipped()
                }
            }
            .overlay(alignment: .top) {
                if !notch.isHardwareNotch && !expanded && !peeking {
                    collapsedHint
                }
            }
    }

    /// One footprint, two arrangements: the resting ring row, or — while a
    /// ring is hovered — that ring slid to the left edge with its bars
    /// unfolded in the space the others vacate.
    ///
    /// Every ring stays in the tree the whole time; the unhovered ones just
    /// collapse to zero width. Nothing is removed mid-hover, so no view can
    /// fire a spurious "unhover" as it disappears, and the gauges keep their
    /// fill instead of replaying their intro when the row returns.
    private func tray(_ providers: [ProviderKind], detailIndex: Int?) -> some View {
        HStack(spacing: detailIndex == nil ? NotchGeometry.tileSpacing : 0) {
            ForEach(Array(providers.enumerated()), id: \.element) { item in
                let isFocused = detailIndex == item.offset
                let isCollapsed = detailIndex != nil && !isFocused
                tile(kind: item.element, index: item.offset, isFocused: isFocused)
                    .frame(width: isCollapsed ? 0 : NotchGeometry.tileWidth)
                    .scaleEffect(isCollapsed ? 0.5 : 1)
                    .opacity(isCollapsed ? 0 : 1)
                    .allowsHitTesting(!isCollapsed)
            }

            if let detailIndex {
                let kind = providers[detailIndex]
                NotchInlineDetail(
                    state: store.state(for: kind),
                    accent: Color(hudHex: settings.accentHex(for: kind)),
                    notice: store.notice(for: kind)
                )
                .padding(.leading, NotchGeometry.detailInnerSpacing)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(x: 18))
                            .combined(with: .blurFade(radius: 6)),
                        removal: .opacity.combined(with: .blurFade(radius: 4))
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: detailIndex == nil ? .center : .leading)
        .padding(.top, NotchGeometry.trayTopPadding)
        .padding(.bottom, NotchGeometry.trayBottomPadding)
        .padding(.horizontal, NotchGeometry.trayHorizontalPadding)
        .contentShape(Rectangle())
        // The one place hover ever *clears*: the pointer demonstrably leaving
        // the whole tray surface. A tile losing hover is usually just the
        // layout sliding out from under a stationary pointer.
        .onHover { hovering in
            guard !hovering, notch.hoveredIndex != nil else { return }
            withAnimation(reduceMotion ? nil : HUDMotion.detail) {
                notch.hoveredIndex = nil
            }
        }
        .onTapGesture(perform: openHUD)
    }

    private func tile(kind: ProviderKind, index: Int, isFocused: Bool) -> some View {
        NotchProviderTile(
            kind: kind,
            state: store.state(for: kind),
            status: store.visualStatus(for: kind),
            accent: Color(hudHex: settings.accentHex(for: kind)),
            index: index,
            isFocused: isFocused,
            open: openHUD,
            hoverChanged: { hovering in
                // Tiles only ever *gain* focus here — clearing belongs to the
                // tray's own exit, or the swap flaps.
                guard hovering, notch.hoveredIndex != index else { return }
                withAnimation(reduceMotion ? nil : HUDMotion.detail) {
                    notch.hoveredIndex = index
                }
            }
        )
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.4, anchor: .top)
                    .combined(with: .opacity)
                    .combined(with: .offset(y: -14))
                    .combined(with: .blurFade(radius: 5)),
                // A plain evaporation: anything fancier would fight the
                // hovered ring's matched-geometry flight to the detail.
                removal: .opacity.combined(with: .blurFade(radius: 5))
            )
        )
        .transaction { transaction in
            guard !reduceMotion else {
                transaction.animation = nil
                return
            }
            if !notch.isExpanded {
                // Rings snap back together on close — a staggered retract
                // reads as lag.
                transaction.animation = .spring(response: 0.24, dampingFraction: 0.9)
            } else if notch.hoveredIndex == nil {
                // Cascade out of the notch left to right, both on first open
                // and when the row returns after a detail closes.
                transaction.animation = .spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.055)
            } else {
                // Swapping to the detail: everything moves on the one spring.
                transaction.animation = HUDMotion.detail
            }
        }
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

/// A ring in the row: the ring column plus hit-testing. It never leaves the
/// tree while the tray is open — hovering just changes how much room it gets.
private struct NotchProviderTile: View {
    let kind: ProviderKind
    let state: ProviderState
    let status: ProviderVisualStatus
    let accent: Color
    let index: Int
    /// This ring's detail is the tray's current content.
    let isFocused: Bool
    let open: () -> Void
    let hoverChanged: (Bool) -> Void

    var body: some View {
        RingColumn(
            kind: kind,
            state: state,
            status: status,
            accent: accent,
            isEmphasized: isFocused,
            index: index
        )
        .frame(width: NotchGeometry.tileWidth)
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .onTapGesture(perform: open)
    }
}

/// One provider's ring with its percent underneath.
private struct RingColumn: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ProviderKind
    let state: ProviderState
    let status: ProviderVisualStatus
    let accent: Color
    /// The hovered ring keeps its glow while its detail is open.
    let isEmphasized: Bool
    let index: Int
    /// Skips the fill-in animation so the preview render harness captures the
    /// settled state instead of frame zero.
    private static let startFilled = ProcessInfo.processInfo.environment["RENDER_NOTCH_PREVIEWS"] == "1"
    @State private var hasAppeared = RingColumn.startFilled

    private var remaining: Double? { state.usage?.primary.remainingPercent }

    var body: some View {
        VStack(spacing: NotchGeometry.ringToPercentGap) {
            ring
            percentLabel
        }
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

    /// Half the arc's line width: keeps the stroke fully inside the frame.
    /// A hairline, not a band — the ring should read as an instrument marking,
    /// and the tray's premium feel dies the moment it turns into a donut chart.
    private static let arcInset: CGFloat = 1
    private static let arcLineWidth: CGFloat = 2

    private var ring: some View {
        ZStack {
            bloom

            // Matte face: a whisper of fill so the ring reads as an object on
            // the glass, flat like the hardware it hangs from. Focus warms it
            // with the provider's colour rather than blooming behind it.
            Circle()
                .inset(by: Self.arcInset + Self.arcLineWidth / 2)
                .fill(isEmphasized ? accent.opacity(0.14) : Color.white.opacity(0.05))

            // The full track, so the arc always has a visible path to ride.
            Circle()
                .inset(by: Self.arcInset)
                .stroke(Color.white.opacity(0.12), lineWidth: Self.arcLineWidth)

            arc

            ProviderGlyph(kind: kind)
                .foregroundStyle(Color.white.opacity(remaining == nil ? 0.35 : 0.92))
                .frame(width: NotchGeometry.ringDiameter * 0.4, height: NotchGeometry.ringDiameter * 0.4)
        }
        .frame(width: NotchGeometry.ringDiameter, height: NotchGeometry.ringDiameter)
    }

    /// Flat at rest, like the mock the tray is styled after; colour only
    /// appears as focus (hover) or life (a streaming session breathing).
    @ViewBuilder
    private var bloom: some View {
        if status == .live, !reduceMotion, !isEmphasized {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let breath = HUDMotion.breath(context.date)
                Circle()
                    .fill(accent)
                    .opacity(0.08 + 0.12 * breath)
                    .blur(radius: 12)
                    .scaleEffect(1.05 + 0.05 * breath)
            }
        }
    }

    @ViewBuilder
    private var arc: some View {
        let fraction = hasAppeared ? (remaining ?? 0) / 100 : 0
        // `stroke` straddles the inset circle's path, so its centreline — the
        // orbit the droplet must ride — is at the inset radius itself.
        let tipRadius = NotchGeometry.ringDiameter / 2 - Self.arcInset

        Circle()
            .inset(by: Self.arcInset)
            .trim(from: 0, to: fraction)
            .stroke(accent, style: StrokeStyle(lineWidth: Self.arcLineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .saturation(status == .stale ? 0.35 : 1)
            .animation(reduceMotion ? nil : HUDMotion.value, value: remaining ?? 0)

        // A bright droplet riding the leading edge of the arc, so a sweep is
        // something moving, not just a length changing. A full ring has no
        // leading edge — at 100% the droplet fades out rather than sitting on
        // the seam where the arc meets its own start.
        if let remaining {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 3.5, height: 3.5)
                .shadow(color: accent.opacity(0.9), radius: 2.5)
                .offset(y: -tipRadius)
                .rotationEffect(.degrees(fraction * 360))
                .saturation(status == .stale ? 0.35 : 1)
                .opacity(hasAppeared && remaining < 100 ? 1 : 0)
                .animation(reduceMotion ? nil : HUDMotion.value, value: remaining)
        }
    }

    @ViewBuilder
    private var percentLabel: some View {
        if let remaining {
            Text("\(Int(remaining.rounded()))%")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(isEmphasized ? 0.95 : 0.6))
                .contentTransition(.numericText(value: remaining))
                .animation(reduceMotion ? nil : HUDMotion.value, value: remaining)
                // The stale bead hangs just under the number, in the tray's
                // bottom padding — an overlay so a tile is the same height
                // whether its data is fresh or not.
                .overlay(alignment: .bottom) {
                    if status == .stale {
                        Circle()
                            .fill(HUDStatusPalette.amber)
                            .frame(width: 5, height: 5)
                            .offset(y: 7)
                    }
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : -5)
        } else if case let .cooling(until) = status {
            // The cooldown is a designed state, not an error: the ring counts
            // down to its own recovery.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(UsageFormatting.durationText(max(1, until.timeIntervalSince(context.date))))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HUDStatusPalette.amber.opacity(0.9))
            }
        } else {
            Text(state.isFailed ? "ERR" : "—")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(state.isFailed ? HUDStatusPalette.amber.opacity(0.8) : Color.white.opacity(0.45))
        }
    }

    private var accessibilityText: String {
        guard let remaining else { return "\(kind.displayName) usage unavailable" }
        return "\(kind.displayName), \(Int(remaining.rounded())) percent remaining"
    }
}

// MARK: - Detail, unfolded beside the ring

/// The compact bars that morph out next to a hovered ring. No header — the
/// ring beside them already says which provider this is — and no divider: the
/// tile is one piece, not a card inside a card.
private struct NotchInlineDetail: View {
    let state: ProviderState
    let accent: Color
    let notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch state {
            case let .loaded(usage):
                row(usage.primary, title: "Session")
                if let secondary = usage.secondary {
                    row(secondary, title: "Week")
                }
            case .loading:
                message("Checking limits…")
            case let .failed(text):
                message(notice ?? text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ window: UsageWindow, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(window.remainingPercent.rounded()))% · \(resetText(window.resetsAt, now: context.date))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.7), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(3, geometry.size.width * window.remainingPercent / 100))
                        .shadow(color: accent.opacity(0.35), radius: 2.5)
                }
            }
            .frame(height: 3)
        }
    }

    private func resetText(_ date: Date?, now: Date) -> String {
        guard let date else { return "no reset" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "resetting" }
        return "\(UsageFormatting.durationText(seconds)) left"
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    /// it most of the way to the hardware notch's matte black, leaving only
    /// the refracted edges and specular highlights showing through.
    static let scrimOpacity: Double = 0.56

    let shape: NotchTrayShape
    let expanded: Bool

    var body: some View {
#if canImport(FoundationModels) // proxy for "built against the macOS 26+ SDK"
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(
                    // `interactive` lets the material itself answer the
                    // pointer with the system's liquid shimmer.
                    .regular.tint(Color.black.opacity(expanded ? Self.tintStrength : 1)).interactive(),
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

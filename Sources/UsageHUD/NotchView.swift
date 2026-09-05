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
    /// The staggered cascade is the tray's *arrival*; once a detail has
    /// opened, the row has already arrived, and bringing it back with fresh
    /// per-ring delays leaves rings mid-flight for a pointer that sweeps
    /// straight back in. After that first hover everything moves as one.
    @State private var rowHasSettled = false

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
        let theme = settings.notchTheme
        let width = expanded
            ? NotchGeometry.expandedWidth(notch: notchMetrics, providerCount: providers.count, theme: theme)
            : closedWidth
        let height = expanded
            ? notch.notchSize.height + theme.trayHeight
            : notch.notchSize.height + (peeking ? NotchGeometry.peekHeightGrowth : 0)

        return ZStack(alignment: .top) {
            // The window stays at its largest size so only the shape animates.
            Color.clear

            shelf(width: width, height: height, expanded: expanded, peeking: peeking, providers: providers, detailIndex: detailIndex)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded {
                notch.hoveredIndex = nil
                rowHasSettled = false
            }
        }
        .onChange(of: notch.hoveredIndex) { _, index in
            if index != nil { rowHasSettled = true }
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
        return ZStack {
            // The shadow caster: a plain fill of the same shape, sitting
            // under the material. Shadows are computed from rendered alpha,
            // and the glass material has none SwiftUI can read — a shadow
            // put on the glass itself falls from its rectangle, not its
            // outline. The caster is black, which is what the near-opaque
            // glass shows through to anyway.
            shape.fill(Color.black)
                // Two shadows, the way a real object casts them: a tight
                // contact shadow that pins the tray to the bezel, and a
                // softer ambient one that lifts it off the desktop. The peek
                // casts a whisper of the ambient one, so the notch visibly
                // wakes before it moves. Both must fade to nothing well
                // inside `NotchGeometry.shadowPadding`, or the window edge
                // slices them into a visible rectangle.
                .shadow(
                    color: .black.opacity(expanded ? 0.35 : 0),
                    radius: 3,
                    y: 1.5
                )
                .shadow(
                    color: .black.opacity(expanded ? 0.42 : (peeking ? 0.3 : 0)),
                    radius: expanded ? 12 : 6,
                    y: expanded ? 7 : 3
                )

            TraySurface(shape: shape, expanded: expanded, matte: settings.notchTrayDark)
        }
            .overlay(
                // Specular rim: brightest along the top flare where the tray
                // meets the screen edge — the catch that makes it read as a
                // physical object sliding out of the housing — and a second,
                // softer glint along the free-hanging bottom lip where the
                // desktop's light would graze it.
                shape.stroke(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.16), location: 0),
                            .init(color: Color.white.opacity(0.035), location: 0.28),
                            .init(color: Color.white.opacity(0.02), location: 0.7),
                            .init(color: Color.white.opacity(0.11), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .opacity(expanded ? 1 : (peeking ? 0.5 : 0))
            )
            .overlay(alignment: .bottom) {
                // The peek's tell: a hairline of provider colour along the
                // bottom lip, so the notch is visibly awake before it moves.
                peekHairline
                    .opacity(peeking ? 1 : 0)
                    .padding(.bottom, 1.5)
            }
            .frame(height: height)
            .animation(reduceMotion ? nil : (expanded ? HUDMotion.openHeight : HUDMotion.close), value: expanded)
            .frame(width: width)
            .animation(reduceMotion ? nil : (expanded ? HUDMotion.openWidth : HUDMotion.close), value: expanded)
            // A collapsed tray would otherwise paint a black bar over the menu
            // bar on displays with no camera housing to hide behind — unless
            // the pointer is already parked there, in which case the peek IS
            // the affordance the housing would have provided.
            .opacity(expanded || peeking || notch.isHardwareNotch ? 1 : 0)
            .overlay {
                // A single specular sweep as the tray opens: light travelling
                // across a surface that has just arrived. Once, never looped.
                if expanded, !reduceMotion {
                    TraySheen()
                        .padding(.top, notch.notchSize.height)
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
            }
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
        content(providers, detailIndex: detailIndex)
        // A soft pool of light behind the row so the rings sit *on* something
        // rather than floating in a void — and a shade of depth just under
        // the housing so the tray reads as recessed beneath it. The matte
        // tray skips both: its whole point is black behind the icons.
        .background {
            if !settings.notchTrayDark {
                floorLight
            }
        }
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

    /// Only a pool of light, never a shade: the content area is narrower than
    /// the shape's top strip beside the housing, so anything that darkens it
    /// from the top draws a visible seam against the glass above.
    private var floorLight: some View {
        RadialGradient(
            colors: [Color.white.opacity(0.075), Color.white.opacity(0)],
            center: UnitPoint(x: 0.5, y: 0.42),
            startRadius: 0,
            endRadius: 120
        )
        .scaleEffect(x: 1.5, y: 1)
        .allowsHitTesting(false)
    }

    /// Picks the tray design the user chose. Classic lives here; the others
    /// live in `NotchThemeViews`, sharing this shell.
    @ViewBuilder
    private func content(_ providers: [ProviderKind], detailIndex: Int?) -> some View {
        let context = NotchTrayContext(
            providers: providers,
            store: store,
            settings: settings,
            detailIndex: detailIndex,
            reduceMotion: reduceMotion,
            focus: { index in focus(index) },
            tileAnimation: { index in tileAnimation(index: index) }
        )
        switch settings.notchTheme {
        case .classic: classicRow(providers, detailIndex: detailIndex)
        case .instrument: InstrumentTray(context: context)
        case .capsule: CapsuleTray(context: context)
        case .concentric: ConcentricTray(context: context)
        case .ledger: LedgerTray(context: context)
        case .segmented: SegmentedTray(context: context)
        }
    }

    /// The pointer landed on a provider: make it the tray's detail. Tiles
    /// only ever *gain* focus this way — clearing belongs to the tray's own
    /// exit, so a layout sliding under a stationary pointer cannot flap.
    private func focus(_ index: Int) {
        guard notch.hoveredIndex != index else { return }
        withAnimation(reduceMotion ? nil : HUDMotion.detail) {
            notch.hoveredIndex = index
        }
    }

    /// The animation a tile uses for whatever change is in flight.
    private func tileAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        if !notch.isExpanded {
            // Rings snap back together on close — a staggered retract reads
            // as lag.
            return .spring(response: 0.24, dampingFraction: 0.9)
        } else if notch.hoveredIndex == nil, !rowHasSettled {
            // Cascade out of the notch left to right on first open.
            return .spring(response: 0.42, dampingFraction: 0.7).delay(Double(index) * 0.055)
        } else {
            // Swapping to a detail, or the row returning from one: everything
            // moves on the one spring, with no stagger, so a pointer sweeping
            // back in never catches a ring mid-flight.
            return HUDMotion.detail
        }
    }

    private func classicRow(_ providers: [ProviderKind], detailIndex: Int?) -> some View {
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
                // Keyed by provider, so a fast hop from one ring to another
                // crossfades the bars instead of rewriting them in place
                // while the old ones are still fading.
                .id(kind)
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
                if hovering { focus(index) }
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
        .transaction { $0.animation = tileAnimation(index: index) }
    }

    private var providerGradient: LinearGradient {
        LinearGradient(
            colors: visibleProviders.map { Color(hudHex: settings.accentHex(for: $0)) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var peekHairline: some View {
        Capsule()
            .fill(providerGradient)
            .frame(width: max(24, notch.notchSize.width * 0.28), height: 1.5)
            .shadow(color: Color.white.opacity(0.35), radius: 3)
            .opacity(0.85)
    }

    /// Without a camera housing there is nothing on screen to hint at the hot
    /// zone, so leave a hairline of provider colour at the top edge.
    private var collapsedHint: some View {
        Capsule()
            .fill(providerGradient)
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
            halo

            // The face: lit from above, so the ring reads as a small domed
            // object sitting on the glass rather than a flat disc painted on
            // it. Focus warms the light with the provider's colour.
            Circle()
                .inset(by: Self.arcInset + Self.arcLineWidth / 2)
                .fill(
                    RadialGradient(
                        colors: isEmphasized
                            ? [accent.opacity(0.28), accent.opacity(0.08)]
                            : [Color.white.opacity(0.11), Color.white.opacity(0.03)],
                        center: UnitPoint(x: 0.5, y: 0.22),
                        startRadius: 0,
                        endRadius: NotchGeometry.ringDiameter * 0.62
                    )
                )
                // A hairline of light along the top of the face: the same
                // specular catch the tray's rim has, in miniature.
                .overlay(
                    Circle()
                        .inset(by: Self.arcInset + Self.arcLineWidth / 2 + 0.5)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.75
                        )
                )

            // The full track, so the arc always has a visible path to ride.
            Circle()
                .inset(by: Self.arcInset)
                .stroke(Color.white.opacity(0.1), lineWidth: Self.arcLineWidth)

            arc

            ProviderGlyph(kind: kind)
                .foregroundStyle(Color.white.opacity(remaining == nil ? 0.35 : 0.94))
                .shadow(color: Color.black.opacity(0.35), radius: 1, y: 0.5)
                .frame(width: NotchGeometry.ringDiameter * 0.4, height: NotchGeometry.ringDiameter * 0.4)
        }
        .frame(width: NotchGeometry.ringDiameter, height: NotchGeometry.ringDiameter)
        // Focus lifts the ring toward the pointer a touch. No animation of
        // its own: it rides the same transaction that slides the ring, so the
        // lift and the slide are one motion.
        .scaleEffect(isEmphasized ? 1.06 : 1)
    }

    /// The focused ring's light spills onto the tray around it.
    @ViewBuilder
    private var halo: some View {
        Circle()
            .fill(accent)
            .blur(radius: 10)
            .scaleEffect(1.2)
            .opacity(isEmphasized ? 0.28 : 0)
    }

    @ViewBuilder
    private var arc: some View {
        let fraction = hasAppeared ? (remaining ?? 0) / 100 : 0
        // `stroke` straddles the inset circle's path, so its centreline — the
        // orbit the droplet must ride — is at the inset radius itself.
        let tipRadius = NotchGeometry.ringDiameter / 2 - Self.arcInset

        // The arc itself is drawn twice: once soft and wide underneath so it
        // glows into the tray, once crisp on top. It brightens toward its
        // leading edge — the light is *at* the tip, and the tail is what it
        // leaves behind.
        let arcGradient = AngularGradient(
            stops: [
                .init(color: accent.opacity(0.55), location: 0),
                .init(color: accent, location: max(0.001, fraction)),
                .init(color: accent, location: 1)
            ],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360)
        )
        let arcStyle = StrokeStyle(lineWidth: Self.arcLineWidth, lineCap: .round)

        Circle()
            .inset(by: Self.arcInset)
            .trim(from: 0, to: fraction)
            .stroke(accent, style: StrokeStyle(lineWidth: Self.arcLineWidth + 2, lineCap: .round))
            .blur(radius: 3)
            .opacity(0.5)
            .rotationEffect(.degrees(-90))
            .saturation(status == .stale ? 0.35 : 1)
            .animation(reduceMotion ? nil : HUDMotion.value, value: remaining ?? 0)

        Circle()
            .inset(by: Self.arcInset)
            .trim(from: 0, to: fraction)
            .stroke(arcGradient, style: arcStyle)
            .rotationEffect(.degrees(-90))
            .saturation(status == .stale ? 0.35 : 1)
            .animation(reduceMotion ? nil : HUDMotion.value, value: remaining ?? 0)

        // A bright droplet riding the leading edge of the arc, so a sweep is
        // something moving, not just a length changing. A full ring has no
        // leading edge — at 100% the droplet fades out rather than sitting on
        // the seam where the arc meets its own start.
        if let remaining {
            Circle()
                .fill(Color.white)
                .frame(width: 3.5, height: 3.5)
                .shadow(color: Color.white.opacity(0.6), radius: 1)
                .shadow(color: accent.opacity(0.9), radius: 3)
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
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .tracking(-0.2)
                .foregroundStyle(Color.white.opacity(isEmphasized ? 0.96 : 0.66))
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
            TimelineView(MinuteCountdownSchedule(resetsAt: [until])) { context in
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
                row(usage.primary, title: usage.primary.displayTitle)
                if let secondary = usage.secondary {
                    row(secondary, title: secondary.displayTitle)
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
            TimelineView(MinuteCountdownSchedule(resetsAt: [window.resetsAt])) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    // The number carries the weight; the countdown is the
                    // footnote beside it.
                    (
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fontWeight(.semibold)
                        + Text("  \(NotchThemeStyle.resetText(window.resetsAt, now: context.date))")
                            .foregroundStyle(Color.white.opacity(0.42))
                            .fontWeight(.medium)
                    )
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
            GeometryReader { geometry in
                let fill = max(4, geometry.size.width * window.remainingPercent / 100)
                ZStack(alignment: .leading) {
                    // A recessed channel for the fill to sit in.
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                        )
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent.opacity(0.6), accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        // A glass-tube highlight along the top of the fill.
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.32), Color.white.opacity(0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .padding(.bottom, 1.5)
                        )
                        .frame(width: fill)
                        .shadow(color: accent.opacity(0.45), radius: 3)
                        // The bar's own droplet: the bright point where the
                        // fill ends, matching the tip riding the ring.
                        .overlay(alignment: .trailing) {
                            Circle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2.5, height: 2.5)
                                .shadow(color: accent, radius: 2)
                                .padding(.trailing, 0.75)
                                .opacity(window.remainingPercent < 100 ? 1 : 0)
                        }
                        .animation(HUDMotion.value, value: window.remainingPercent)
                }
            }
            .frame(height: 4)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sheen

/// A soft diagonal band of light that crosses the tray once as it opens.
private struct TraySheen: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let bandWidth = geometry.size.width * 0.45
            let travel = geometry.size.width + bandWidth
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0), location: 0),
                    .init(color: Color.white.opacity(0.07), location: 0.45),
                    .init(color: Color.white.opacity(0.12), location: 0.5),
                    .init(color: Color.white.opacity(0.07), location: 0.55),
                    .init(color: Color.white.opacity(0), location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: bandWidth, height: geometry.size.height * 2.2)
            .rotationEffect(.degrees(22))
            .offset(x: -bandWidth + travel * progress)
            // No blend mode here, deliberately: a blend mode inside the
            // transparent panel forces the whole hosting view into an opaque
            // backing, which paints the panel's full rectangle grey.
        }
        .onAppear {
            // Starts a beat after the shape has begun to unfold, and moves at
            // the pace of the tray's own spring so it feels like the same
            // event, not a decoration layered on afterwards.
            withAnimation(.easeInOut(duration: 0.8).delay(0.18)) {
                progress = 1
            }
        }
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
    /// Plain matte black, the way the camera housing itself is drawn, with
    /// no glass to refract the desktop behind it.
    let matte: Bool

    var body: some View {
#if canImport(FoundationModels) // proxy for "built against the macOS 26+ SDK"
        if matte {
            shape.fill(Color.black)
        } else if #available(macOS 26.0, *) {
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

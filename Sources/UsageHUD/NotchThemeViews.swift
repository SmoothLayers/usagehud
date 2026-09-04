import SwiftUI

// The five tray designs beyond Classic. Each draws the content inside the
// shell that `NotchShelfView` owns; the shell handles the shape, rim, shadow,
// peek and open/close motion, and hands the content everything it needs
// through `NotchTrayContext`.

/// What a themed tray needs from the shelf that hosts it.
@MainActor
struct NotchTrayContext {
    let providers: [ProviderKind]
    let store: UsageStore
    let settings: AppSettings
    /// Index of the provider whose detail is showing, if any.
    let detailIndex: Int?
    let reduceMotion: Bool
    /// The pointer landed on a provider: make it the tray's detail.
    let focus: (Int) -> Void
    /// The animation a tile should use for the change in flight — the first
    /// open cascades, everything after moves on one spring.
    let tileAnimation: (Int) -> Animation?

    func accent(_ kind: ProviderKind) -> Color { Color(hudHex: settings.accentHex(for: kind)) }
    func state(_ kind: ProviderKind) -> ProviderState { store.state(for: kind) }
    func status(_ kind: ProviderKind) -> ProviderVisualStatus { store.visualStatus(for: kind) }
    func usage(_ kind: ProviderKind) -> ProviderUsage? { state(kind).usage }
    func remaining(_ kind: ProviderKind) -> Double? { usage(kind)?.primary.remainingPercent }
    func notice(_ kind: ProviderKind) -> String? { store.notice(for: kind) }
    func isFocused(_ index: Int) -> Bool { detailIndex == index }
    /// Another provider holds the detail, so this one steps back.
    func isDimmed(_ index: Int) -> Bool { detailIndex != nil && detailIndex != index }
}

// MARK: - Shared pieces

enum NotchThemeStyle {
    /// Skips the fill-in animation so the preview render harness captures
    /// the settled state instead of frame zero.
    static let startFilled = ProcessInfo.processInfo.environment["RENDER_NOTCH_PREVIEWS"] == "1"

    static let trayTopPadding: CGFloat = 10
    static let trayBottomPadding: CGFloat = 12
    static let trayHorizontalPadding: CGFloat = 14

    static let tileTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.55, anchor: .top)
            .combined(with: .opacity)
            .combined(with: .offset(y: -10))
            .combined(with: .blurFade(radius: 4)),
        removal: .opacity.combined(with: .blurFade(radius: 4))
    )

    static let detailTransition: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .offset(x: 14))
            .combined(with: .blurFade(radius: 5)),
        removal: .opacity.combined(with: .blurFade(radius: 4))
    )

    static func resetText(_ date: Date?, now: Date, suffix: Bool = true) -> String {
        guard let date else { return "no reset" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "resetting" }
        let duration = UsageFormatting.durationText(seconds)
        return suffix ? "\(duration) left" : duration
    }

    static func name(_ kind: ProviderKind) -> String { kind.rawValue.capitalized }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))" }
}

/// A still amber bead beside a provider's figure while its numbers are
/// stale; nothing otherwise. Live sessions deliberately show no extra mark:
/// an accent-coloured dot was too easy to mistake for the stale bead.
private struct StatusDot: View {
    let status: ProviderVisualStatus
    let accent: Color
    var size: CGFloat = 4

    var body: some View {
        if status == .stale {
            Circle()
                .fill(HUDStatusPalette.amber)
                .frame(width: size, height: size)
                .shadow(color: HUDStatusPalette.amber.opacity(0.6), radius: 2.3)
                .accessibilityLabel("Data is stale")
        }
    }
}

/// Tracked small capitals in the monospaced face: the label voice of the
/// instrument-style themes.
private struct SmallCaps: View {
    let text: String
    var size: CGFloat = 6.5
    var opacity: Double = 0.42

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.2)
            .foregroundStyle(Color.white.opacity(opacity))
            .lineLimit(1)
    }
}

/// What a tile shows instead of a percent when there is none: a dash while
/// loading, ERR on failure, and a live countdown while a provider cools.
private struct FallbackFigure: View {
    let state: ProviderState
    let status: ProviderVisualStatus
    var size: CGFloat = 9
    var design: Font.Design = .rounded

    var body: some View {
        if case let .cooling(until) = status {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(UsageFormatting.durationText(max(1, until.timeIntervalSince(context.date))))
                    .font(.system(size: size, weight: .bold, design: design))
                    .monospacedDigit()
                    .foregroundStyle(HUDStatusPalette.amber.opacity(0.9))
            }
        } else if case .failed = state {
            Text("ERR")
                .font(.system(size: size, weight: .bold, design: design))
                .foregroundStyle(HUDStatusPalette.amber.opacity(0.8))
        } else {
            Text("—")
                .font(.system(size: size, weight: .bold, design: design))
                .foregroundStyle(Color.white.opacity(0.45))
        }
    }
}

/// The detail's stand-in while a provider is loading or failed.
private struct DetailMessage: View {
    let context: NotchTrayContext
    let kind: ProviderKind
    var design: Font.Design = .rounded

    var body: some View {
        let text: String
        switch context.state(kind) {
        case .loading: text = "Checking limits…"
        case let .failed(message): text = context.notice(kind) ?? message
        case .loaded: text = ""
        }
        return Text(text)
            .font(.system(size: 9.5, weight: .medium, design: design))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The label line above a meter in the monospaced themes: the window's
/// name on the left, its percent and countdown on the right.
///
/// The once-a-second clock wraps the whole line rather than just the
/// countdown: `TimelineView` fills whatever width it is offered, so a clock
/// beside a meter would starve the meter of room.
private struct MonoRowHeader: View {
    let title: String
    let window: UsageWindow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { clock in
            HStack(alignment: .firstTextBaseline) {
                SmallCaps(text: title)
                Spacer(minLength: 6)
                (
                    Text("\(NotchThemeStyle.percent(window.remainingPercent))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white.opacity(0.9))
                    + Text(" · ")
                        .foregroundStyle(Color.white.opacity(0.35))
                    + Text(NotchThemeStyle.resetText(window.resetsAt, now: clock.date))
                        .foregroundStyle(Color.white.opacity(0.55))
                )
                .font(.system(size: 8.5, design: .monospaced))
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }
}

/// A slim capsule meter with a glow under its fill.
private struct MiniBar: View {
    let fraction: Double
    let accent: Color
    var height: CGFloat = 2
    var trackOpacity: Double = 0.1

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(trackOpacity))
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.65), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geometry.size.width * fraction))
                    .shadow(color: accent.opacity(0.45), radius: 2.5)
            }
        }
        .frame(height: height)
        .animation(HUDMotion.value, value: fraction)
    }
}

/// The resting ring row that folds into one ring plus its detail — the
/// arrangement Classic uses, shared by the Instrument and Segmented themes.
///
/// Every ring stays in the tree; the unfocused ones collapse to zero width
/// so nothing is removed mid-hover and the gauges keep their fill.
private struct FocusRowTray<Tile: View, Detail: View>: View {
    let context: NotchTrayContext
    let tileWidth: CGFloat
    let spacing: CGFloat
    let detailSpacing: CGFloat
    @ViewBuilder let tile: (ProviderKind, Int, Bool) -> Tile
    @ViewBuilder let detail: (ProviderKind) -> Detail

    var body: some View {
        let detailIndex = context.detailIndex
        HStack(spacing: detailIndex == nil ? spacing : 0) {
            ForEach(Array(context.providers.enumerated()), id: \.element) { item in
                let isFocused = detailIndex == item.offset
                let isCollapsed = detailIndex != nil && !isFocused
                tile(item.element, item.offset, isFocused)
                    .frame(width: tileWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { context.focus(item.offset) }
                    }
                    .frame(width: isCollapsed ? 0 : tileWidth)
                    .scaleEffect(isCollapsed ? 0.5 : 1)
                    .opacity(isCollapsed ? 0 : 1)
                    .allowsHitTesting(!isCollapsed)
                    .transition(NotchThemeStyle.tileTransition)
                    .transaction { $0.animation = context.tileAnimation(item.offset) }
            }

            if let detailIndex, detailIndex < context.providers.count {
                let kind = context.providers[detailIndex]
                detail(kind)
                    .id(kind)
                    .padding(.leading, detailSpacing)
                    .transition(NotchThemeStyle.detailTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: detailIndex == nil ? .center : .leading)
        .padding(.top, NotchThemeStyle.trayTopPadding)
        .padding(.bottom, NotchThemeStyle.trayBottomPadding)
        .padding(.horizontal, NotchThemeStyle.trayHorizontalPadding)
    }
}

/// Fills itself in on arrival, a beat behind the tile it lives on.
private struct FillIn: ViewModifier {
    let context: NotchTrayContext
    let index: Int
    @Binding var hasAppeared: Bool

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            guard !context.reduceMotion else {
                hasAppeared = true
                return
            }
            withAnimation(.smooth(duration: 0.85).delay(0.1 + Double(index) * 0.055)) {
                hasAppeared = true
            }
        }
    }
}

// MARK: - 1. Instrument

/// A watch dial, not a chart: hairline rings on a tick track, monospaced
/// figures, the provider named in small capitals underneath.
struct InstrumentTray: View {
    let context: NotchTrayContext

    var body: some View {
        FocusRowTray(context: context, tileWidth: 58, spacing: 4, detailSpacing: 12) { kind, index, isFocused in
            InstrumentTile(context: context, kind: kind, index: index, isFocused: isFocused)
        } detail: { kind in
            InstrumentDetail(context: context, kind: kind)
        }
    }
}

private struct InstrumentTile: View {
    let context: NotchTrayContext
    let kind: ProviderKind
    let index: Int
    let isFocused: Bool
    @State private var hasAppeared = NotchThemeStyle.startFilled

    var body: some View {
        let accent = context.accent(kind)
        let status = context.status(kind)
        let remaining = context.remaining(kind)
        VStack(spacing: 4) {
            InstrumentRing(
                kind: kind,
                accent: accent,
                remaining: remaining,
                fraction: hasAppeared ? (remaining ?? 0) / 100 : 0,
                showTip: hasAppeared && (remaining ?? 100) < 100,
                isFocused: isFocused,
                isStale: status == .stale,
                reduceMotion: context.reduceMotion
            )
            if let remaining {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(NotchThemeStyle.percent(remaining))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: remaining))
                    Text("%")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .foregroundStyle(Color.white.opacity(isFocused ? 0.95 : 0.85))
                .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : -4)
            } else {
                FallbackFigure(state: context.state(kind), status: status, size: 9, design: .monospaced)
            }
            HStack(spacing: 4) {
                SmallCaps(text: NotchThemeStyle.name(kind))
                StatusDot(status: status, accent: accent, size: 3.5)
            }
        }
        .modifier(FillIn(context: context, index: index, hasAppeared: $hasAppeared))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "\(kind.displayName), \(Int($0.rounded())) percent remaining" } ?? "\(kind.displayName) usage unavailable")
    }
}

private struct InstrumentRing: View {
    let kind: ProviderKind
    let accent: Color
    let remaining: Double?
    let fraction: Double
    let showTip: Bool
    let isFocused: Bool
    let isStale: Bool
    let reduceMotion: Bool

    private static let diameter: CGFloat = 40
    private static let arcInset: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .fill(accent)
                .blur(radius: 8)
                .scaleEffect(1.15)
                .opacity(isFocused ? 0.25 : 0)

            // The bezel: a track of ticks the arc is read against.
            Circle()
                .inset(by: 0.75)
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [0.5, 2.6]))

            Circle()
                .inset(by: Self.arcInset)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)

            Circle()
                .inset(by: Self.arcInset)
                .trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .blur(radius: 2.5)
                .opacity(0.45)
                .rotationEffect(.degrees(-90))

            Circle()
                .inset(by: Self.arcInset)
                .trim(from: 0, to: fraction)
                .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.white)
                .frame(width: 2.6, height: 2.6)
                .shadow(color: accent.opacity(0.9), radius: 2.5)
                .offset(y: -(Self.diameter / 2 - Self.arcInset))
                .rotationEffect(.degrees(fraction * 360))
                .opacity(showTip ? 1 : 0)

            ProviderGlyph(kind: kind)
                .foregroundStyle(Color.white.opacity(remaining == nil ? 0.35 : 0.92))
                .frame(width: 14, height: 14)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .saturation(isStale ? 0.35 : 1)
        .animation(reduceMotion ? nil : HUDMotion.value, value: remaining ?? 0)
    }
}

private struct InstrumentDetail: View {
    let context: NotchTrayContext
    let kind: ProviderKind

    var body: some View {
        let accent = context.accent(kind)
        VStack(alignment: .leading, spacing: 10) {
            if let usage = context.usage(kind) {
                row(usage.primary.displayTitle, usage.primary, accent: accent)
                if let week = usage.secondary {
                    row(week.displayTitle, week, accent: accent)
                } else if !usage.primary.isWeekly {
                    SmallCaps(text: "No weekly window", opacity: 0.3)
                }
            } else {
                DetailMessage(context: context, kind: kind, design: .monospaced)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ window: UsageWindow, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoRowHeader(title: title, window: window)
            InstrumentScale(fraction: window.remainingPercent / 100, accent: accent)
        }
    }
}

/// A hairline with quarter ticks and a bright droplet at the fill's end.
private struct InstrumentScale: View {
    let fraction: Double
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 1)
                    .offset(y: 3)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { tick in
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 1, height: 7)
                        .offset(x: max(0, min(width - 1, width * tick)))
                }
                Capsule()
                    .fill(accent)
                    .frame(width: max(3, width * fraction), height: 2)
                    .shadow(color: accent.opacity(0.6), radius: 3)
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .shadow(color: accent, radius: 2.5)
                    }
                    .offset(y: 2.5)
            }
            .animation(HUDMotion.value, value: fraction)
        }
        .frame(height: 7)
    }
}

// MARK: - 2. Capsule

/// Three glass pills. Hovering one grows it across the row while the others
/// fold down to their marks: a morph, not a swap.
struct CapsuleTray: View {
    let context: NotchTrayContext

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(context.providers.enumerated()), id: \.element) { item in
                CapsulePill(
                    context: context,
                    kind: item.element,
                    index: item.offset,
                    mode: context.detailIndex == nil ? .resting : (context.isFocused(item.offset) ? .expanded : .folded)
                )
                .transition(NotchThemeStyle.tileTransition)
                .transaction { $0.animation = context.tileAnimation(item.offset) }
            }
        }
        .padding(.top, NotchThemeStyle.trayTopPadding)
        .padding(.bottom, NotchThemeStyle.trayBottomPadding)
        .padding(.horizontal, 12)
    }
}

private struct CapsulePill: View {
    enum Mode { case resting, expanded, folded }

    let context: NotchTrayContext
    let kind: ProviderKind
    let index: Int
    let mode: Mode
    @State private var hasAppeared = NotchThemeStyle.startFilled

    private static let height: CGFloat = 34

    var body: some View {
        let accent = context.accent(kind)
        let status = context.status(kind)
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.065))
                .overlay(
                    Capsule().stroke(
                        LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                )
                .overlay(Capsule().stroke(accent.opacity(mode == .expanded ? 0.35 : 0), lineWidth: 1))
                .shadow(color: accent.opacity(mode == .expanded ? 0.22 : 0), radius: 12)

            content(accent: accent, status: status)
                .padding(.horizontal, mode == .folded ? 0 : 6)
        }
        .frame(height: Self.height)
        .frame(width: mode == .folded ? Self.height : nil)
        .frame(maxWidth: mode == .folded ? Self.height : .infinity)
        .opacity(mode == .folded ? 0.55 : 1)
        .saturation(status == .stale ? 0.35 : 1)
        .contentShape(Capsule())
        .onHover { hovering in
            if hovering { context.focus(index) }
        }
        .modifier(FillIn(context: context, index: index, hasAppeared: $hasAppeared))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.remaining(kind).map { "\(kind.displayName), \(Int($0.rounded())) percent remaining" } ?? "\(kind.displayName) usage unavailable")
    }

    @ViewBuilder
    private func content(accent: Color, status: ProviderVisualStatus) -> some View {
        let remaining = context.remaining(kind)
        switch mode {
        case .folded:
            orb(accent)
        case .resting:
            HStack(spacing: 7) {
                orb(accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        figure(remaining, status: status)
                        StatusDot(status: status, accent: accent)
                    }
                    MiniBar(fraction: hasAppeared ? (remaining ?? 0) / 100 : 0, accent: accent)
                        .frame(width: 34)
                }
                Spacer(minLength: 0)
            }
            .transition(.opacity.combined(with: .blurFade(radius: 4)))
        case .expanded:
            HStack(spacing: 8) {
                orb(accent)
                HStack(spacing: 3) {
                    figure(remaining, status: status)
                    StatusDot(status: status, accent: accent)
                }
                if let usage = context.usage(kind) {
                    TimelineView(.periodic(from: .now, by: 1)) { clock in
                        VStack(alignment: .leading, spacing: 4) {
                            row(usage.primary.displayTitle, usage.primary, accent: accent, now: clock.date)
                            if let week = usage.secondary {
                                row(week.displayTitle, week, accent: accent, now: clock.date)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.trailing, 4)
                } else {
                    DetailMessage(context: context, kind: kind)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .offset(x: 8)).combined(with: .blurFade(radius: 4)))
        }
    }

    private func orb(_ accent: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(0.42), accent.opacity(0.14)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: 14
                )
            )
            .overlay(Circle().stroke(accent.opacity(0.3), lineWidth: 0.75))
            .overlay(
                ProviderGlyph(kind: kind)
                    .foregroundStyle(Color.white)
                    .frame(width: 11, height: 11)
            )
            .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func figure(_ remaining: Double?, status: ProviderVisualStatus) -> some View {
        if let remaining {
            Text("\(NotchThemeStyle.percent(remaining))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: remaining))
                .foregroundStyle(Color.white.opacity(0.94))
                .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining)
                .lineLimit(1)
                .fixedSize()
        } else {
            FallbackFigure(state: context.state(kind), status: status, size: 10)
        }
    }

    private func row(_ title: String, _ window: UsageWindow, accent: Color, now: Date) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 30, alignment: .leading)
            MiniBar(fraction: window.remainingPercent / 100, accent: accent)
                .frame(maxWidth: .infinity)
            // The bare countdown: "left" would cost the meter its room.
            Text(NotchThemeStyle.resetText(window.resetsAt, now: now, suffix: false))
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3. Concentric

/// One gauge of nested arcs with a legend beside it: every provider read at
/// once, in the least room.
struct ConcentricTray: View {
    let context: NotchTrayContext
    @State private var hasAppeared = NotchThemeStyle.startFilled

    var body: some View {
        HStack(spacing: 12) {
            ConcentricGauge(context: context, hasAppeared: hasAppeared)
            VStack(spacing: 3) {
                ForEach(Array(context.providers.enumerated()), id: \.element) { item in
                    ConcentricLegendRow(context: context, kind: item.element, index: item.offset)
                        .transition(NotchThemeStyle.tileTransition)
                        .transaction { $0.animation = context.tileAnimation(item.offset) }
                }
            }
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NotchThemeStyle.trayTopPadding)
        .padding(.bottom, NotchThemeStyle.trayBottomPadding)
        .padding(.horizontal, NotchThemeStyle.trayHorizontalPadding)
        .modifier(FillIn(context: context, index: 0, hasAppeared: $hasAppeared))
    }
}

private struct ConcentricGauge: View {
    let context: NotchTrayContext
    let hasAppeared: Bool

    private static let diameter: CGFloat = 66
    /// Arcs open at the bottom like a speedometer.
    private static let sweep: Double = 0.75

    var body: some View {
        ZStack {
            ForEach(Array(context.providers.enumerated()), id: \.element) { item in
                let inset = 2 + CGFloat(item.offset) * 6
                let accent = context.accent(item.element)
                let remaining = context.remaining(item.element)
                let focused = context.isFocused(item.offset)
                let dimmed = context.isDimmed(item.offset)

                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: Self.sweep)
                    .stroke(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: hasAppeared ? Self.sweep * (remaining ?? 0) / 100 : 0)
                    .stroke(accent, style: StrokeStyle(lineWidth: focused ? 4.5 : 3.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .shadow(color: accent.opacity(0.5), radius: 2)
                    .opacity(dimmed ? 0.25 : 1)
                    .saturation(context.status(item.element) == .stale ? 0.35 : 1)
                    .animation(context.reduceMotion ? nil : .smooth(duration: 0.9).delay(Double(item.offset) * 0.11), value: hasAppeared)
                    .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining ?? 0)
            }

            if let index = context.detailIndex, index < context.providers.count {
                ProviderGlyph(kind: context.providers[index])
                    .foregroundStyle(Color.white)
                    .frame(width: 12, height: 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                HStack(spacing: 3) {
                    ForEach(context.providers, id: \.self) { kind in
                        Circle()
                            .fill(context.accent(kind))
                            .frame(width: 4, height: 4)
                            .shadow(color: context.accent(kind), radius: 2)
                    }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }
}

private struct ConcentricLegendRow: View {
    let context: NotchTrayContext
    let kind: ProviderKind
    let index: Int

    var body: some View {
        let accent = context.accent(kind)
        let status = context.status(kind)
        let focused = context.isFocused(index)
        let dimmed = context.isDimmed(index)
        let remaining = context.remaining(kind)

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 5, height: 5)
                    .shadow(color: accent.opacity(0.8), radius: 3)
                Text(NotchThemeStyle.name(kind))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                StatusDot(status: status, accent: accent)
                Spacer(minLength: 4)
                if let remaining {
                    Text("\(NotchThemeStyle.percent(remaining))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: remaining))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining)
                } else {
                    FallbackFigure(state: context.state(kind), status: status, size: 8.5)
                }
                MiniBar(fraction: (remaining ?? 0) / 100, accent: accent, height: 3)
                    .frame(width: 30)
            }
            if focused {
                subline
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: focused ? 30 : (dimmed ? 15 : 17))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
                .opacity(focused ? 1 : 0)
        )
        .opacity(dimmed ? 0.45 : 1)
        .saturation(status == .stale ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { context.focus(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "\(kind.displayName), \(Int($0.rounded())) percent remaining" } ?? "\(kind.displayName) usage unavailable")
    }

    @ViewBuilder
    private var subline: some View {
        if let usage = context.usage(kind) {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                HStack(spacing: 0) {
                    Text("Resets in ")
                    Text(NotchThemeStyle.resetText(usage.primary.resetsAt, now: clock.date, suffix: false))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white.opacity(0.85))
                    if let week = usage.secondary {
                        Text(" · Week ")
                        Text("\(NotchThemeStyle.percent(week.remainingPercent))%")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                }
            }
            .font(.system(size: 7.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.5))
            .lineLimit(1)
            .padding(.leading, 11)
        } else {
            DetailMessage(context: context, kind: kind)
                .padding(.leading, 11)
        }
    }
}

// MARK: - 4. Ledger

/// No rings. The number is the design: large figures set in hairline
/// columns with a line of progress under each.
struct LedgerTray: View {
    let context: NotchTrayContext
    @State private var hasAppeared = NotchThemeStyle.startFilled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(context.providers.enumerated()), id: \.element) { item in
                if item.offset > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 1)
                        .padding(.vertical, 4)
                }
                LedgerColumn(context: context, kind: item.element, index: item.offset, hasAppeared: hasAppeared)
                    .transition(NotchThemeStyle.tileTransition)
                    .transaction { $0.animation = context.tileAnimation(item.offset) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, NotchThemeStyle.trayTopPadding)
        .padding(.bottom, NotchThemeStyle.trayBottomPadding)
        .padding(.horizontal, NotchThemeStyle.trayHorizontalPadding)
        .modifier(FillIn(context: context, index: 0, hasAppeared: $hasAppeared))
    }
}

private struct LedgerColumn: View {
    let context: NotchTrayContext
    let kind: ProviderKind
    let index: Int
    let hasAppeared: Bool

    var body: some View {
        let accent = context.accent(kind)
        let status = context.status(kind)
        let focused = context.isFocused(index)
        let folded = context.isDimmed(index)
        let usage = context.usage(kind)
        let remaining = usage?.primary.remainingPercent

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .shadow(color: accent.opacity(0.8), radius: 3)
                // A folded column keeps its dot and figure; the name would
                // only truncate in the room it has left.
                if !folded {
                    SmallCaps(text: NotchThemeStyle.name(kind), opacity: 0.5)
                }
                StatusDot(status: status, accent: accent, size: 3.5)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let remaining {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(NotchThemeStyle.percent(remaining))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .tracking(-1)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: remaining))
                        if !folded {
                            Text("%")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    }
                    .foregroundStyle(Color.white.opacity(0.95))
                    .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining)
                    .fixedSize()
                } else {
                    FallbackFigure(state: context.state(kind), status: status, size: 14)
                        .frame(height: 24)
                }

                if focused {
                    aside(usage)
                        .transition(.opacity.combined(with: .offset(x: 6)).combined(with: .blurFade(radius: 4)))
                }
            }

            VStack(spacing: 3) {
                hair(fraction: hasAppeared ? (remaining ?? 0) / 100 : 0, accent: accent, opacity: 1)
                if focused, let week = usage?.secondary {
                    hair(fraction: week.remainingPercent / 100, accent: accent, opacity: 0.6)
                        .transition(.opacity.combined(with: .offset(y: 3)))
                }
            }
        }
        .padding(.horizontal, folded ? 8 : 10)
        .frame(minWidth: folded ? 56 : nil, maxWidth: folded ? 56 : .infinity, alignment: .leading)
        .clipped()
        .layoutPriority(focused ? 2 : 1)
        .opacity(folded ? 0.4 : 1)
        .saturation(status == .stale ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { context.focus(index) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "\(kind.displayName), \(Int($0.rounded())) percent remaining" } ?? "\(kind.displayName) usage unavailable")
    }

    @ViewBuilder
    private func aside(_ usage: ProviderUsage?) -> some View {
        if let usage {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 0) {
                        Text("Session · ")
                        Text(NotchThemeStyle.resetText(usage.primary.resetsAt, now: clock.date))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white.opacity(0.88))
                    }
                    if let week = usage.secondary {
                        HStack(spacing: 0) {
                            Text("Week ")
                            Text("\(NotchThemeStyle.percent(week.remainingPercent))%")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.white.opacity(0.88))
                            Text(" · ")
                            Text(NotchThemeStyle.resetText(week.resetsAt, now: clock.date))
                        }
                    } else {
                        Text("No weekly window").opacity(0.6)
                    }
                }
            }
            .font(.system(size: 7.5, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.5))
            .lineLimit(1)
            .fixedSize()
        } else {
            DetailMessage(context: context, kind: kind)
        }
    }

    private func hair(fraction: Double, accent: Color, opacity: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.1))
            GeometryReader { geometry in
                Capsule()
                    .fill(accent)
                    .frame(width: max(2, geometry.size.width * fraction))
                    .shadow(color: accent.opacity(0.6), radius: 3)
                    .opacity(opacity)
                    .animation(HUDMotion.value, value: fraction)
            }
        }
        .frame(height: 1.5)
    }
}

// MARK: - 5. Segmented

/// Rings built from discrete cells that light one by one, like a level meter
/// on studio gear. The last lit cell is white: the edge you can count to.
struct SegmentedTray: View {
    let context: NotchTrayContext

    var body: some View {
        FocusRowTray(context: context, tileWidth: 58, spacing: 4, detailSpacing: 12) { kind, index, isFocused in
            SegmentedTile(context: context, kind: kind, index: index, isFocused: isFocused)
        } detail: { kind in
            SegmentedDetail(context: context, kind: kind)
        }
    }
}

private enum Segments {
    static let count = 28
    static let diameter: CGFloat = 40
    static let inset: CGFloat = 2.5
    static var dash: [CGFloat] {
        let circumference = 2 * CGFloat.pi * (diameter / 2 - inset)
        let segment = circumference / CGFloat(count)
        return [segment * 0.7, segment * 0.3]
    }
    static func lit(_ remaining: Double?) -> Int {
        guard let remaining else { return 0 }
        return Int((remaining / 100 * Double(count)).rounded())
    }
}

private struct SegmentedTile: View {
    let context: NotchTrayContext
    let kind: ProviderKind
    let index: Int
    let isFocused: Bool
    @State private var hasAppeared = NotchThemeStyle.startFilled

    var body: some View {
        let accent = context.accent(kind)
        let status = context.status(kind)
        let remaining = context.remaining(kind)
        VStack(spacing: 4) {
            SegmentedRing(
                kind: kind,
                accent: accent,
                lit: hasAppeared ? Segments.lit(remaining) : 0,
                target: Segments.lit(remaining),
                hasValue: remaining != nil,
                isFocused: isFocused,
                isStale: status == .stale,
                reduceMotion: context.reduceMotion
            )
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let remaining {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(NotchThemeStyle.percent(remaining))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: remaining))
                        Text("%")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .foregroundStyle(Color.white.opacity(isFocused ? 0.95 : 0.88))
                    .animation(context.reduceMotion ? nil : HUDMotion.value, value: remaining)
                } else {
                    FallbackFigure(state: context.state(kind), status: status, size: 9, design: .monospaced)
                }
                StatusDot(status: status, accent: accent, size: 3.5)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : -4)
        }
        .modifier(FillIn(context: context, index: index, hasAppeared: $hasAppeared))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remaining.map { "\(kind.displayName), \(Int($0.rounded())) percent remaining" } ?? "\(kind.displayName) usage unavailable")
    }
}

private struct SegmentedRing: View {
    let kind: ProviderKind
    let accent: Color
    let lit: Int
    let target: Int
    let hasValue: Bool
    let isFocused: Bool
    let isStale: Bool
    let reduceMotion: Bool

    var body: some View {
        let style = StrokeStyle(lineWidth: 3, dash: Segments.dash)
        let fraction = Double(lit) / Double(Segments.count)
        ZStack {
            Circle()
                .fill(accent)
                .blur(radius: 8)
                .scaleEffect(1.15)
                .opacity(isFocused ? 0.25 : 0)

            Circle()
                .inset(by: Segments.inset)
                .stroke(Color.white.opacity(0.11), style: style)
                .rotationEffect(.degrees(-90))

            Circle()
                .inset(by: Segments.inset)
                .trim(from: 0, to: fraction)
                .stroke(accent, style: style)
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.6), radius: 2)

            Circle()
                .inset(by: Segments.inset)
                .trim(from: max(0, fraction - 1 / Double(Segments.count)), to: fraction)
                .stroke(Color.white, style: style)
                .rotationEffect(.degrees(-90))
                .opacity(lit > 0 ? 1 : 0)

            ProviderGlyph(kind: kind)
                .foregroundStyle(Color.white.opacity(hasValue ? 0.92 : 0.35))
                .frame(width: 13, height: 13)
        }
        .frame(width: Segments.diameter, height: Segments.diameter)
        .saturation(isStale ? 0.35 : 1)
        // Cells light at a steady 24 a second, so a fuller ring takes longer:
        // a count, not a sweep.
        .animation(reduceMotion ? nil : .linear(duration: Double(max(1, target)) / 24).delay(0.15), value: lit)
    }
}

private struct SegmentedDetail: View {
    let context: NotchTrayContext
    let kind: ProviderKind

    var body: some View {
        let accent = context.accent(kind)
        VStack(alignment: .leading, spacing: 10) {
            if let usage = context.usage(kind) {
                row(usage.primary.displayTitle, usage.primary, accent: accent)
                if let week = usage.secondary {
                    row(week.displayTitle, week, accent: accent)
                } else if !usage.primary.isWeekly {
                    SmallCaps(text: "No weekly window", opacity: 0.3)
                }
            } else {
                DetailMessage(context: context, kind: kind, design: .monospaced)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ window: UsageWindow, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoRowHeader(title: title, window: window)
            CellBar(fraction: window.remainingPercent / 100, accent: accent)
        }
    }
}

/// Twenty cells; the lit ones glow and the last is white.
private struct CellBar: View {
    let fraction: Double
    let accent: Color
    @State private var hasAppeared = NotchThemeStyle.startFilled

    private static let count = 20

    var body: some View {
        let lit = Int((fraction * Double(Self.count)).rounded())
        HStack(spacing: 1.5) {
            ForEach(0..<Self.count, id: \.self) { cell in
                let isLit = cell < lit
                let isEdge = cell == lit - 1
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isEdge ? Color.white : accent)
                            .shadow(color: accent.opacity(0.5), radius: 2)
                            .opacity(isLit && hasAppeared ? 1 : 0)
                            .animation(.easeOut(duration: 0.12).delay(0.1 + Double(cell) * 0.02), value: hasAppeared)
                    )
                    .frame(height: 4)
            }
        }
        .onAppear { hasAppeared = true }
    }
}

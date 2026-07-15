import SwiftUI

private enum HUDPalette {
    static let ink = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let panel = Color(red: 0.085, green: 0.098, blue: 0.11)
    static let muted = Color.white.opacity(0.48)
}

struct HUDView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusPulse = false
    let hide: () -> Void

    var body: some View {
        Group {
            if store.isCompact {
                compactHUD
            } else {
                expandedHUD
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                statusPulse = true
            }
        }
    }

    private var expandedHUD: some View {
        VStack(spacing: 14) {
            header
            HStack(spacing: 10) {
                if settings.showCodex {
                    ProviderCard(
                        kind: .codex,
                        state: store.codex,
                        compact: false,
                        notice: nil,
                        lastSuccess: store.codexLastSuccess,
                        nextRefresh: store.codexNextRefresh,
                        accent: Color(hudHex: settings.codexAccentHex),
                        barThickness: settings.barThickness,
                        cornerRadius: settings.cornerRadius,
                        textScale: settings.textScale,
                        showResetCountdown: settings.showResetCountdown,
                        showRefreshCountdown: settings.showRefreshCountdown
                    )
                }
                if settings.showClaude {
                    ProviderCard(
                        kind: .claude,
                        state: store.claude,
                        compact: false,
                        notice: store.claudeNotice,
                        lastSuccess: store.claudeLastSuccess,
                        nextRefresh: store.claudeNextRefresh,
                        accent: Color(hudHex: settings.claudeAccentHex),
                        barThickness: settings.barThickness,
                        cornerRadius: settings.cornerRadius,
                        textScale: settings.textScale,
                        showResetCountdown: settings.showResetCountdown,
                        showRefreshCountdown: settings.showRefreshCountdown
                    )
                }
            }
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity, alignment: .top)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: settings.cornerRadius + 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: settings.cornerRadius + 6, style: .continuous)
                    .fill(HUDPalette.ink.opacity(0.88))
                RoundedRectangle(cornerRadius: settings.cornerRadius + 6, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
        )
        .padding(20)
    }

    private var compactHUD: some View {
        let layout = settings.compactLayout == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))
        return VStack(spacing: 7) {
            CompactRefreshRail(store: store, settings: settings)
            layout {
                if settings.showCodex {
                    CompactUsageStrip(
                        kind: .codex,
                        state: store.codex,
                        notice: nil,
                        lastSuccess: store.codexLastSuccess,
                        nextRefresh: store.codexNextRefresh,
                        accent: Color(hudHex: settings.codexAccentHex),
                        barThickness: settings.barThickness,
                        cornerRadius: settings.cornerRadius,
                        textScale: settings.textScale,
                        showResetCountdown: settings.showResetCountdown
                    )
                }
                if settings.showClaude {
                    CompactUsageStrip(
                        kind: .claude,
                        state: store.claude,
                        notice: store.claudeNotice,
                        lastSuccess: store.claudeLastSuccess,
                        nextRefresh: store.claudeNextRefresh,
                        accent: Color(hudHex: settings.claudeAccentHex),
                        barThickness: settings.barThickness,
                        cornerRadius: settings.cornerRadius,
                        textScale: settings.textScale,
                        showResetCountdown: settings.showResetCountdown
                    )
                }
            }
        }
        .frame(minWidth: 252, maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text("USAGE HUD")
                .font(.system(size: 10 * settings.textScale, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.68))
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .shadow(color: statusColor.opacity(statusPulse ? 0.8 : 0.2), radius: statusPulse ? 5 : 1)
                .opacity(reduceMotion ? 1 : (statusPulse ? 1 : 0.65))
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 180 : 0))
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.2),
                        value: store.isRefreshing
                    )
            }
            .help("Refresh now")
            Button(action: store.toggleCompact) {
                Image(systemName: store.isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
            }
            .help(store.isCompact ? "Expand" : "Compact")
            Button(action: hide) {
                Image(systemName: "xmark")
            }
            .help("Hide HUD")
        }
        .buttonStyle(HUDIconButtonStyle())
    }

    private var statusColor: Color {
        if settings.showCodex, store.codex.usage != nil { return Color(hudHex: settings.codexAccentHex) }
        if settings.showClaude, store.claude.usage != nil { return Color(hudHex: settings.claudeAccentHex) }
        return settings.showCodex
            ? Color(hudHex: settings.codexAccentHex)
            : Color(hudHex: settings.claudeAccentHex)
    }
}

private struct CompactRefreshRail: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if settings.showRefreshCountdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        Text("POLL")
                            .tracking(0.8)
                        if settings.showCodex {
                            timer(
                                "C",
                                date: store.codexNextRefresh,
                                color: Color(hudHex: settings.codexAccentHex),
                                now: context.date
                            )
                        }
                        if settings.showCodex, settings.showClaude {
                            Text("·").foregroundStyle(HUDPalette.muted)
                        }
                        if settings.showClaude {
                            timer(
                                "A",
                                date: store.claudeNextRefresh,
                                color: Color(hudHex: settings.claudeAccentHex),
                                now: context.date
                            )
                        }
                    }
                    .font(.system(size: 7 * settings.textScale, weight: .bold, design: .monospaced))
                    .foregroundStyle(HUDPalette.muted)
                }
            }
            Spacer(minLength: 8)
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing && !reduceMotion ? 180 : 0))
                    .animation(
                        store.isRefreshing && !reduceMotion
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.2),
                        value: store.isRefreshing
                    )
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
    }

    private func timer(_ label: String, date: Date?, color: Color, now: Date) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(color)
            Text(UsageFormatting.refreshCountdownValueText(for: date, now: now))
                .foregroundStyle(Color.white.opacity(0.72))
                .monospacedDigit()
        }
    }
}

private struct CompactUsageStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ProviderKind
    let state: ProviderState
    let notice: String?
    let lastSuccess: Date?
    let nextRefresh: Date?
    let accent: Color
    let barThickness: Double
    let cornerRadius: Double
    let textScale: Double
    let showResetCountdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                loading
            case let .failed(message):
                failure(message)
            case let .loaded(usage):
                loaded(usage)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(HUDPalette.panel.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
        .help(UsageFormatting.timingHelp(lastSuccess: lastSuccess, nextRefresh: nextRefresh))
    }

    private func loaded(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                providerLabel
                if let notice {
                    Text("STALE")
                        .font(.system(size: 7 * textScale, weight: .black, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.32))
                        .help(notice)
                }
                Spacer()
                Text(usage.primary.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 19 * textScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.95))
                    .contentTransition(.numericText(value: usage.primary.remainingPercent))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: usage.primary.remainingPercent)
                Text("%")
                    .font(.system(size: 10 * textScale, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
                Text("LEFT")
                    .font(.system(size: 7 * textScale, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(HUDPalette.muted)
            }

            UsageBar(remaining: usage.primary.remainingPercent, accent: accent, thickness: barThickness)

            HStack(spacing: 5) {
                Text(usage.primary.label.uppercased())
                if showResetCountdown {
                    Text("·")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(UsageFormatting.resetCountdownText(for: usage.primary.resetsAt, now: context.date))
                    }
                }
                Spacer(minLength: 8)
                if let secondary = usage.secondary {
                    Text("WEEK \(Int(secondary.remainingPercent.rounded()))%")
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .font(.system(size: 8 * textScale, weight: .semibold, design: .monospaced))
            .foregroundStyle(HUDPalette.muted)
            .lineLimit(1)
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            providerLabel
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(accent)
            Text("CHECKING")
                .font(.system(size: 8 * textScale, weight: .bold, design: .monospaced))
                .foregroundStyle(HUDPalette.muted)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                providerLabel
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
            }
            Text(message)
                .font(.system(size: 8 * textScale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
        }
    }

    private var providerLabel: some View {
        Text(kind.displayName)
            .font(.system(size: 10 * textScale, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(accent)
    }

}

private struct ProviderCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ProviderKind
    let state: ProviderState
    let compact: Bool
    let notice: String?
    let lastSuccess: Date?
    let nextRefresh: Date?
    let accent: Color
    let barThickness: Double
    let cornerRadius: Double
    let textScale: Double
    let showResetCountdown: Bool
    let showRefreshCountdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack {
                Text(kind.displayName)
                    .font(.system(size: 10 * textScale, weight: .black, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(accent)
                Spacer()
                if let notice {
                    Text("STALE")
                        .font(.system(size: 8 * textScale, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.32))
                        .help(notice)
                } else if let plan = state.usage?.plan, !compact {
                    Text(plan.uppercased())
                        .font(.system(size: 8 * textScale, weight: .bold, design: .monospaced))
                        .foregroundStyle(HUDPalette.muted)
                        .lineLimit(1)
                }
            }

            switch state {
            case .loading:
                loading
            case let .failed(message):
                failure(message)
            case let .loaded(usage):
                loaded(usage)
            }

            if !compact {
                Spacer(minLength: 0)
            }

            if !compact, lastSuccess != nil || nextRefresh != nil {
                ProviderTimingLine(
                    lastSuccess: lastSuccess,
                    nextRefresh: nextRefresh,
                    accent: accent,
                    textScale: textScale,
                    showRefreshCountdown: showRefreshCountdown
                )
            }
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 76 : 158, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(HUDPalette.panel.opacity(0.92))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func loaded(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(usage.primary.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: (compact ? 25 : 36) * textScale, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.94))
                    .contentTransition(.numericText(value: usage.primary.remainingPercent))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: usage.primary.remainingPercent)
                Text("%")
                    .font(.system(size: (compact ? 12 : 14) * textScale, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text("LEFT")
                    .font(.system(size: 8 * textScale, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(HUDPalette.muted)
            }

            UsageBar(remaining: usage.primary.remainingPercent, accent: accent, thickness: barThickness)

            if !compact {
                HStack {
                    Text(usage.primary.label)
                    Spacer()
                    if showResetCountdown {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(UsageFormatting.resetCountdownText(for: usage.primary.resetsAt, now: context.date))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
                .font(.system(size: 9 * textScale, weight: .medium, design: .monospaced))
                .foregroundStyle(HUDPalette.muted)

                if let secondary = usage.secondary {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Text("WEEK")
                            .tracking(1)
                        Spacer()
                        Text("\(Int(secondary.remainingPercent.rounded()))% left")
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    .font(.system(size: 9 * textScale, weight: .bold, design: .monospaced))
                    .foregroundStyle(HUDPalette.muted)
                }
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView().controlSize(.small).tint(accent)
            Text("CHECKING LIMITS")
                .font(.system(size: 9 * textScale, weight: .bold, design: .monospaced))
                .foregroundStyle(HUDPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(accent)
            Text(message)
                .font(.system(size: 9 * textScale, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(compact ? 2 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct ProviderTimingLine: View {
    let lastSuccess: Date?
    let nextRefresh: Date?
    let accent: Color
    let textScale: Double
    let showRefreshCountdown: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: showRefreshCountdown ? 1 : 30)) { context in
            HStack(spacing: 5) {
                Circle()
                    .fill(accent.opacity(0.75))
                    .frame(width: 4, height: 4)
                Text(UsageFormatting.updatedStatusText(for: lastSuccess, now: context.date))
                if showRefreshCountdown {
                    Spacer(minLength: 6)
                    Text(UsageFormatting.refreshCountdownText(for: nextRefresh, now: context.date))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 7 * textScale, weight: .bold, design: .monospaced))
            .tracking(0.4)
            .foregroundStyle(HUDPalette.muted)
        }
    }
}

private struct UsageBar: View {
    let remaining: Double
    let accent: Color
    let thickness: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedRemaining: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.72), accent, Color.white.opacity(0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(3, geometry.size.width * displayedRemaining / 100))
                    .shadow(color: accent.opacity(0.45), radius: 5)
            }
        }
        .frame(height: thickness)
        .onAppear { displayedRemaining = remaining }
        .onChange(of: remaining) { _, newValue in
            if reduceMotion {
                displayedRemaining = newValue
            } else {
                withAnimation(.smooth(duration: 0.65)) { displayedRemaining = newValue }
            }
        }
        .accessibilityLabel("\(Int(remaining.rounded())) percent remaining")
    }
}

private struct HUDIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.95 : 0.52))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.05)))
            .contentShape(Circle())
    }
}

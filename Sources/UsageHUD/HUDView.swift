import SwiftUI

private enum HUDPalette {
    static let ink = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let panel = Color(red: 0.085, green: 0.098, blue: 0.11)
    static let codex = Color(red: 0.33, green: 0.91, blue: 0.73)
    static let claude = Color(red: 0.96, green: 0.58, blue: 0.39)
    static let muted = Color.white.opacity(0.48)
}

struct HUDView: View {
    @ObservedObject var store: UsageStore
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
    }

    private var expandedHUD: some View {
        VStack(spacing: 14) {
            header
            HStack(spacing: 10) {
                ProviderCard(kind: .codex, state: store.codex, compact: false, notice: nil)
                ProviderCard(kind: .claude, state: store.claude, compact: false, notice: store.claudeNotice)
            }
        }
        .padding(14)
        .frame(width: 390)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(HUDPalette.ink.opacity(0.88))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
        )
        .padding(20)
    }

    private var compactHUD: some View {
        VStack(spacing: 8) {
            CompactUsageStrip(kind: .codex, state: store.codex, notice: nil)
            CompactUsageStrip(kind: .claude, state: store.claude, notice: store.claudeNotice)
        }
        .frame(width: 322)
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text("USAGE HUD")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.white.opacity(0.68))
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
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
        if store.codex.usage != nil || store.claude.usage != nil { return HUDPalette.codex }
        return HUDPalette.claude
    }
}

private struct CompactUsageStrip: View {
    let kind: ProviderKind
    let state: ProviderState
    let notice: String?

    private var accent: Color { kind == .codex ? HUDPalette.codex : HUDPalette.claude }

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
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(HUDPalette.panel.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
    }

    private func loaded(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                providerLabel
                if let notice {
                    Text("STALE")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.32))
                        .help(notice)
                }
                Spacer()
                Text(usage.primary.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.95))
                Text("%")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
                Text("LEFT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(HUDPalette.muted)
            }

            UsageBar(remaining: usage.primary.remainingPercent, accent: accent)

            HStack(spacing: 5) {
                Text(usage.primary.label.uppercased())
                Text("·")
                Text(compactResetText(for: usage.primary.resetsAt))
                Spacer(minLength: 8)
                if let secondary = usage.secondary {
                    Text("WEEK \(Int(secondary.remainingPercent.rounded()))%")
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 8, weight: .bold, design: .monospaced))
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
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.64))
                .lineLimit(1)
        }
    }

    private var providerLabel: some View {
        Text(kind.displayName)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(accent)
    }

    private func compactResetText(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "RESET —" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "RESETTING" }

        let minutes = max(1, Int(remaining / 60))
        if minutes < 60 { return "RESET \(minutes)M" }

        let hours = minutes / 60
        let leftoverMinutes = minutes % 60
        if hours < 24 {
            return leftoverMinutes == 0 ? "RESET \(hours)H" : "RESET \(hours)H \(leftoverMinutes)M"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "RESET \(formatter.string(from: date).uppercased())"
    }
}

private struct ProviderCard: View {
    let kind: ProviderKind
    let state: ProviderState
    let compact: Bool
    let notice: String?

    private var accent: Color { kind == .codex ? HUDPalette.codex : HUDPalette.claude }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack {
                Text(kind.displayName)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(accent)
                Spacer()
                if let notice {
                    Text("STALE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color(red: 1, green: 0.76, blue: 0.32))
                        .help(notice)
                } else if let plan = state.usage?.plan, !compact {
                    Text(plan.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
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
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 76 : 142, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(HUDPalette.panel.opacity(0.92))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func loaded(_ usage: ProviderUsage) -> some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(usage.primary.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: compact ? 25 : 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.94))
                Text("%")
                    .font(.system(size: compact ? 12 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text("LEFT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(HUDPalette.muted)
            }

            UsageBar(remaining: usage.primary.remainingPercent, accent: accent)

            if !compact {
                HStack {
                    Text(usage.primary.label)
                    Spacer()
                    Text(UsageFormatting.resetText(for: usage.primary.resetsAt))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(HUDPalette.muted)
                }
            }
        }
    }

    private var loading: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView().controlSize(.small).tint(accent)
            Text("CHECKING LIMITS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(compact ? 2 : 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct UsageBar: View {
    let remaining: Double
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(accent)
                    .frame(width: max(3, geometry.size.width * remaining / 100))
                    .shadow(color: accent.opacity(0.45), radius: 5)
            }
        }
        .frame(height: 4)
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

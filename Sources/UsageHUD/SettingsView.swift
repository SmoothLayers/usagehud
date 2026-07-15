import SwiftUI

private enum SettingsPalette {
    static let ink = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let panel = Color(red: 0.085, green: 0.098, blue: 0.11)
    static let codex = Color(red: 0.33, green: 0.91, blue: 0.73)
    static let claude = Color(red: 0.96, green: 0.58, blue: 0.39)
    static let muted = Color.white.opacity(0.5)
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: UsageStore
    @ObservedObject var updateChecker: UpdateChecker
    let setUsageAlerts: (Bool) -> Void
    let checkForUpdates: () -> Void
    let resetWindowSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    refreshSection
                    displaySection
                    appearanceSection
                    alertSection
                    updateSection
                }
                .padding(.trailing, 4)
            }
        }
        .padding(20)
        .frame(width: 520, height: 720)
        .background(SettingsPalette.ink)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsPalette.codex.opacity(0.12))
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SettingsPalette.codex)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("USAGE HUD // CONTROL PANEL")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Local display and refresh preferences")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsPalette.muted)
            }
            Spacer()
            Text("V\(AppMetadata.version)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SettingsPalette.muted)
        }
    }

    private var refreshSection: some View {
        InstrumentSection(title: "REFRESH CADENCE", detail: "Each visible provider uses its own timer") {
            HStack(spacing: 8) {
                ForEach(AppSettings.pollingChoices, id: \.self) { interval in
                    let selected = settings.pollingInterval == interval
                    Button {
                        settings.setPollingInterval(interval)
                    } label: {
                        Text("\(Int(interval / 60)) MIN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(selected ? SettingsPalette.codex.opacity(0.18) : Color.white.opacity(0.045))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(selected ? SettingsPalette.codex.opacity(0.8) : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? SettingsPalette.codex : Color.white.opacity(0.72))
                }
            }
        }
    }

    private var displaySection: some View {
        InstrumentSection(title: "DISPLAY", detail: "At least one provider stays visible") {
            VStack(spacing: 12) {
                HStack(spacing: 18) {
                    providerToggle(.codex, isOn: settings.showCodex, accent: SettingsPalette.codex)
                    providerToggle(.claude, isOn: settings.showClaude, accent: SettingsPalette.claude)
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    SettingLabel(title: "COMPACT MODE", detail: "Floating meter strips")
                    Spacer()
                    InstrumentToggle(isOn: store.isCompact, tint: SettingsPalette.codex) {
                        store.toggleCompact()
                    }
                }

                HStack {
                    SettingLabel(title: "MENU BAR USAGE", detail: "Show C72 · A39 beside the gauge")
                    Spacer()
                    InstrumentToggle(isOn: settings.showMenuBarUsage, tint: SettingsPalette.codex) {
                        settings.setShowMenuBarUsage(!settings.showMenuBarUsage)
                    }
                }

                HStack(spacing: 18) {
                    HStack {
                        SettingLabel(title: "RESET COUNTER", detail: "Countdown to usage reset")
                        Spacer()
                        InstrumentToggle(isOn: settings.showResetCountdown, tint: SettingsPalette.codex) {
                            settings.setShowResetCountdown(!settings.showResetCountdown)
                        }
                    }
                    HStack {
                        SettingLabel(title: "REFRESH COUNTER", detail: "Countdown to the next check")
                        Spacer()
                        InstrumentToggle(isOn: settings.showRefreshCountdown, tint: SettingsPalette.claude) {
                            settings.setShowRefreshCountdown(!settings.showRefreshCountdown)
                        }
                    }
                }

                HStack(spacing: 18) {
                    HStack {
                        SettingLabel(title: "LOCK HUD", detail: "Prevent moving and resizing")
                        Spacer()
                        InstrumentToggle(isOn: settings.lockHUD, tint: SettingsPalette.codex) {
                            settings.setLockHUD(!settings.lockHUD)
                        }
                    }
                    HStack {
                        SettingLabel(title: "CLICK THROUGH", detail: "Send clicks to windows below")
                        Spacer()
                        InstrumentToggle(isOn: settings.clickThrough, tint: SettingsPalette.claude) {
                            settings.setClickThrough(!settings.clickThrough)
                        }
                    }
                }

                HStack {
                    SettingLabel(title: "WINDOW SIZE", detail: "Restore the current mode to its normal dimensions")
                    Spacer()
                    Button(action: resetWindowSize) {
                        Label("RESET", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SettingsPalette.codex)
                    .help("Reset the current HUD mode to its default size")
                }

            }
        }
    }

    private var appearanceSection: some View {
        InstrumentSection(title: "APPEARANCE", detail: "Tune the HUD instrument readout") {
            VStack(spacing: 11) {
                appearanceChoiceRow(
                    title: "TEXT SIZE", detail: "Scale labels and values",
                    values: AppSettings.textScaleChoices, labels: ["S", "M", "L", "XL"],
                    selected: settings.textScale, setValue: settings.setTextScale
                )
                appearanceChoiceRow(
                    title: "METER", detail: "Usage bar thickness",
                    values: AppSettings.barThicknessChoices, labels: ["3", "4", "6", "8"],
                    selected: settings.barThickness, setValue: settings.setBarThickness
                )
                appearanceChoiceRow(
                    title: "CORNERS", detail: "Panel corner radius",
                    values: AppSettings.cornerRadiusChoices, labels: ["10", "14", "18", "24"],
                    selected: settings.cornerRadius, setValue: settings.setCornerRadius
                )

                HStack {
                    SettingLabel(title: "COMPACT FLOW", detail: "Stack bars or place them side by side")
                    Spacer()
                    CompactChoiceButton(title: "VERT", selected: settings.compactLayout == .vertical) {
                        settings.setCompactLayout(.vertical)
                    }
                    CompactChoiceButton(title: "HORIZ", selected: settings.compactLayout == .horizontal) {
                        settings.setCompactLayout(.horizontal)
                    }
                }

                HStack(spacing: 12) {
                    SettingLabel(title: "HUD OPACITY", detail: "\(Int(settings.hudOpacity * 100))%")
                        .frame(width: 116, alignment: .leading)
                    Slider(value: Binding(get: { settings.hudOpacity }, set: settings.setHUDOpacity), in: 0.6...1)
                        .tint(Color(hudHex: settings.codexAccentHex))
                }

                accentRow(provider: .codex, selected: settings.codexAccentHex)
                accentRow(provider: .claude, selected: settings.claudeAccentHex)
            }
        }
    }

    private func appearanceChoiceRow(
        title: String,
        detail: String,
        values: [Double],
        labels: [String],
        selected: Double,
        setValue: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            SettingLabel(title: title, detail: detail)
            Spacer()
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                CompactChoiceButton(title: labels[index], selected: selected == value) {
                    setValue(value)
                }
            }
        }
    }

    private func accentRow(provider: ProviderKind, selected: String) -> some View {
        HStack {
            SettingLabel(title: "\(provider.displayName) ACCENT", detail: "Provider channel color")
            Spacer()
            ForEach(HUDAccentPalette.choices, id: \.self) { hex in
                Button { settings.setAccent(hex, provider: provider) } label: {
                    Circle()
                        .fill(Color(hudHex: hex))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.white, lineWidth: selected == hex ? 2 : 0))
                        .padding(2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var alertSection: some View {
        InstrumentSection(title: "USAGE ALERTS", detail: "Notifications stay on this Mac") {
            VStack(spacing: 10) {
                HStack {
                    SettingLabel(title: "LOW USAGE + RESETS", detail: "Set each warning level or turn it off")
                    Spacer()
                    InstrumentToggle(isOn: store.usageAlertsEnabled, tint: SettingsPalette.claude) {
                        setUsageAlerts(!store.usageAlertsEnabled)
                    }
                }
                if store.usageAlertsEnabled {
                    Divider().overlay(Color.white.opacity(0.08))
                    alertThresholdRow(provider: .codex, slot: .primary, accent: SettingsPalette.codex)
                    alertThresholdRow(provider: .codex, slot: .secondary, accent: SettingsPalette.codex)
                    alertThresholdRow(provider: .claude, slot: .primary, accent: SettingsPalette.claude)
                    alertThresholdRow(provider: .claude, slot: .secondary, accent: SettingsPalette.claude)
                }
            }
        }
    }

    private var updateSection: some View {
        InstrumentSection(title: "UPDATES", detail: updateChecker.status.displayText) {
            HStack {
                SettingLabel(title: "AUTOMATIC CHECKS", detail: "Checks GitHub Releases once per day")
                Spacer()
                InstrumentToggle(isOn: settings.automaticUpdateChecks, tint: SettingsPalette.codex) {
                    settings.setAutomaticUpdateChecks(!settings.automaticUpdateChecks)
                }
                Button(action: checkForUpdates) {
                    Text(updateButtonTitle)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .disabled(updateChecker.status == .checking)
            }
        }
    }

    private var updateButtonTitle: String {
        switch updateChecker.status {
        case .checking: return "CHECKING"
        case .available: return "OPEN RELEASE"
        default: return "CHECK NOW"
        }
    }

    private func alertThresholdRow(provider: ProviderKind, slot: UsageAlertSlot, accent: Color) -> some View {
        let threshold = settings.alertThreshold(provider: provider, slot: slot)
        return HStack {
            Circle().fill(accent).frame(width: 5, height: 5)
            SettingLabel(
                title: "\(provider.displayName) \(slot.rawValue.uppercased())",
                detail: slot == .primary ? "Current usage window" : "Long usage window"
            )
            Spacer()
            ThresholdSelector(value: threshold, accent: accent) { value in
                settings.setAlertThreshold(value, provider: provider, slot: slot)
            }
        }
    }

    private func providerToggle(_ provider: ProviderKind, isOn: Bool, accent: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(provider.displayName)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.86))
            Spacer()
            InstrumentToggle(
                isOn: isOn,
                tint: accent,
                disabled: isOn && settings.visibleProviderCount == 1
            ) {
                settings.setProvider(provider, visible: !isOn)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompactChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(selected ? SettingsPalette.codex : Color.white.opacity(0.58))
                .frame(minWidth: 28)
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? SettingsPalette.codex.opacity(0.14) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? SettingsPalette.codex.opacity(0.7) : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ThresholdSelector: View {
    let value: Int
    let accent: Color
    let setValue: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button { move(-1) } label: { Image(systemName: "minus") }
            Text(value == 0 ? "OFF" : "\(value)%")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(value == 0 ? SettingsPalette.muted : accent)
                .frame(width: 34)
            Button { move(1) } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(Color.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08)))
    }

    private func move(_ direction: Int) {
        guard let index = AppSettings.allowedAlertThresholds.firstIndex(of: value) else { return }
        let next = min(AppSettings.allowedAlertThresholds.count - 1, max(0, index + direction))
        setValue(AppSettings.allowedAlertThresholds[next])
    }
}

private struct InstrumentToggle: View {
    let isOn: Bool
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint.opacity(0.38) : Color.white.opacity(0.1))
                Circle()
                    .fill(isOn ? tint : Color.white.opacity(0.55))
                    .padding(3)
                    .shadow(color: isOn ? tint.opacity(0.35) : .clear, radius: 3)
            }
            .frame(width: 38, height: 20)
            .overlay(
                Capsule()
                    .stroke(isOn ? tint.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .opacity(disabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(isOn ? "On" : "Off")
    }
}

private struct InstrumentSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                Text(detail)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(SettingsPalette.muted)
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(SettingsPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }
}

private struct SettingLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(SettingsPalette.muted)
        }
    }
}

import Foundation

enum AppSettingsChange {
    case polling
    case providers
    case appearance
    case menuBar
    case alerts
    case interaction
    case updates
    case layout
    case sizing
    case timers
}

final class AppSettings: ObservableObject {
    static let pollingChoices: [TimeInterval] = [2 * 60, 5 * 60, 10 * 60, 15 * 60]
    static let defaultPollingInterval: TimeInterval = 2 * 60

    @Published private(set) var pollingInterval: TimeInterval
    @Published private(set) var showCodex: Bool
    @Published private(set) var showClaude: Bool
    @Published private(set) var hudOpacity: Double
    @Published private(set) var showMenuBarUsage: Bool
    @Published private(set) var showResetCountdown: Bool
    @Published private(set) var showRefreshCountdown: Bool
    @Published private(set) var alertThresholds: [String: Int]
    @Published private(set) var lockHUD: Bool
    @Published private(set) var clickThrough: Bool
    @Published private(set) var automaticUpdateChecks: Bool
    @Published private(set) var textScale: Double
    @Published private(set) var barThickness: Double
    @Published private(set) var cornerRadius: Double
    @Published private(set) var compactLayout: CompactLayout
    @Published private(set) var codexAccentHex: String
    @Published private(set) var claudeAccentHex: String

    var changed: ((AppSettingsChange) -> Void)?

    private let defaults: UserDefaults
    private enum Key {
        static let pollingInterval = "pollingInterval"
        static let showCodex = "showCodex"
        static let showClaude = "showClaude"
        static let hudOpacity = "hudOpacity"
        static let showMenuBarUsage = "showMenuBarUsage"
        static let showResetCountdown = "showResetCountdown"
        static let showRefreshCountdown = "showRefreshCountdown"
        static let lockHUD = "lockHUD"
        static let clickThrough = "clickThrough"
        static let automaticUpdateChecks = "automaticUpdateChecks"
        static let textScale = "textScale"
        static let barThickness = "barThickness"
        static let cornerRadius = "cornerRadius"
        static let compactLayout = "compactLayout"
        static let codexAccentHex = "codexAccentHex"
        static let claudeAccentHex = "claudeAccentHex"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedInterval = defaults.double(forKey: Key.pollingInterval)
        pollingInterval = Self.pollingChoices.contains(savedInterval)
            ? savedInterval
            : Self.defaultPollingInterval
        let savedShowCodex = defaults.object(forKey: Key.showCodex) == nil
            ? true
            : defaults.bool(forKey: Key.showCodex)
        let savedShowClaude = defaults.object(forKey: Key.showClaude) == nil
            ? true
            : defaults.bool(forKey: Key.showClaude)
        showCodex = !savedShowCodex && !savedShowClaude ? true : savedShowCodex
        showClaude = savedShowClaude
        let savedOpacity = defaults.double(forKey: Key.hudOpacity)
        hudOpacity = defaults.object(forKey: Key.hudOpacity) == nil
            ? 1
            : min(1, max(0.6, savedOpacity))
        showMenuBarUsage = defaults.bool(forKey: Key.showMenuBarUsage)
        showResetCountdown = defaults.object(forKey: Key.showResetCountdown) == nil
            ? true
            : defaults.bool(forKey: Key.showResetCountdown)
        showRefreshCountdown = defaults.object(forKey: Key.showRefreshCountdown) == nil
            ? true
            : defaults.bool(forKey: Key.showRefreshCountdown)
        var thresholds: [String: Int] = [:]
        for provider in ProviderKind.allCases {
            for slot in UsageAlertSlot.allCases {
                let key = Self.alertThresholdKey(provider: provider, slot: slot)
                let saved = defaults.object(forKey: key) == nil ? 20 : defaults.integer(forKey: key)
                thresholds[key] = Self.allowedAlertThresholds.contains(saved) ? saved : 20
            }
        }
        alertThresholds = thresholds
        lockHUD = defaults.bool(forKey: Key.lockHUD)
        clickThrough = defaults.bool(forKey: Key.clickThrough)
        automaticUpdateChecks = defaults.object(forKey: Key.automaticUpdateChecks) == nil
            ? true
            : defaults.bool(forKey: Key.automaticUpdateChecks)
        textScale = Self.savedChoice(defaults.double(forKey: Key.textScale), choices: Self.textScaleChoices, fallback: 1)
        barThickness = Self.savedChoice(defaults.double(forKey: Key.barThickness), choices: Self.barThicknessChoices, fallback: 4)
        cornerRadius = Self.savedChoice(defaults.double(forKey: Key.cornerRadius), choices: Self.cornerRadiusChoices, fallback: 14)
        compactLayout = CompactLayout(rawValue: defaults.string(forKey: Key.compactLayout) ?? "") ?? .vertical
        let savedCodexAccent = defaults.string(forKey: Key.codexAccentHex) ?? HUDAccentPalette.codexDefault
        codexAccentHex = HUDAccentPalette.choices.contains(savedCodexAccent) ? savedCodexAccent : HUDAccentPalette.codexDefault
        let savedClaudeAccent = defaults.string(forKey: Key.claudeAccentHex) ?? HUDAccentPalette.claudeDefault
        claudeAccentHex = HUDAccentPalette.choices.contains(savedClaudeAccent) ? savedClaudeAccent : HUDAccentPalette.claudeDefault
    }

    var visibleProviderCount: Int {
        (showCodex ? 1 : 0) + (showClaude ? 1 : 0)
    }

    func setPollingInterval(_ interval: TimeInterval) {
        guard Self.pollingChoices.contains(interval), pollingInterval != interval else { return }
        pollingInterval = interval
        defaults.set(interval, forKey: Key.pollingInterval)
        changed?(.polling)
    }

    func setProvider(_ provider: ProviderKind, visible: Bool) {
        let current = provider == .codex ? showCodex : showClaude
        guard current != visible else { return }
        if !visible && visibleProviderCount == 1 { return }

        if provider == .codex {
            showCodex = visible
            defaults.set(visible, forKey: Key.showCodex)
        } else {
            showClaude = visible
            defaults.set(visible, forKey: Key.showClaude)
        }
        changed?(.providers)
    }

    func setHUDOpacity(_ opacity: Double) {
        let clamped = min(1, max(0.6, opacity))
        guard abs(hudOpacity - clamped) > 0.001 else { return }
        hudOpacity = clamped
        defaults.set(clamped, forKey: Key.hudOpacity)
        changed?(.appearance)
    }

    func setShowMenuBarUsage(_ enabled: Bool) {
        guard showMenuBarUsage != enabled else { return }
        showMenuBarUsage = enabled
        defaults.set(enabled, forKey: Key.showMenuBarUsage)
        changed?(.menuBar)
    }

    func setShowResetCountdown(_ enabled: Bool) {
        guard showResetCountdown != enabled else { return }
        showResetCountdown = enabled
        defaults.set(enabled, forKey: Key.showResetCountdown)
        changed?(.timers)
    }

    func setShowRefreshCountdown(_ enabled: Bool) {
        guard showRefreshCountdown != enabled else { return }
        showRefreshCountdown = enabled
        defaults.set(enabled, forKey: Key.showRefreshCountdown)
        changed?(.timers)
    }

    static let allowedAlertThresholds = [0, 5, 10, 15, 20, 25, 30]
    static let textScaleChoices: [Double] = [0.85, 1, 1.15, 1.3]
    static let barThicknessChoices: [Double] = [3, 4, 6, 8]
    static let cornerRadiusChoices: [Double] = [10, 14, 18, 24]

    func alertThreshold(provider: ProviderKind, slot: UsageAlertSlot) -> Int {
        alertThresholds[Self.alertThresholdKey(provider: provider, slot: slot)] ?? 20
    }

    func setAlertThreshold(_ threshold: Int, provider: ProviderKind, slot: UsageAlertSlot) {
        guard Self.allowedAlertThresholds.contains(threshold) else { return }
        let key = Self.alertThresholdKey(provider: provider, slot: slot)
        guard alertThresholds[key] != threshold else { return }
        alertThresholds[key] = threshold
        defaults.set(threshold, forKey: key)
        changed?(.alerts)
    }

    private static func alertThresholdKey(provider: ProviderKind, slot: UsageAlertSlot) -> String {
        "alertThreshold.\(provider.rawValue).\(slot.rawValue)"
    }

    func setLockHUD(_ enabled: Bool) {
        guard lockHUD != enabled else { return }
        lockHUD = enabled
        defaults.set(enabled, forKey: Key.lockHUD)
        changed?(.interaction)
    }

    func setClickThrough(_ enabled: Bool) {
        guard clickThrough != enabled else { return }
        clickThrough = enabled
        defaults.set(enabled, forKey: Key.clickThrough)
        changed?(.interaction)
    }

    func setAutomaticUpdateChecks(_ enabled: Bool) {
        guard automaticUpdateChecks != enabled else { return }
        automaticUpdateChecks = enabled
        defaults.set(enabled, forKey: Key.automaticUpdateChecks)
        changed?(.updates)
    }

    func setTextScale(_ value: Double) {
        guard Self.textScaleChoices.contains(value), textScale != value else { return }
        textScale = value
        defaults.set(value, forKey: Key.textScale)
        changed?(.sizing)
    }

    func setBarThickness(_ value: Double) {
        setAppearanceChoice(value, choices: Self.barThicknessChoices, current: &barThickness, key: Key.barThickness)
    }

    func setCornerRadius(_ value: Double) {
        setAppearanceChoice(value, choices: Self.cornerRadiusChoices, current: &cornerRadius, key: Key.cornerRadius)
    }

    func setCompactLayout(_ layout: CompactLayout) {
        guard compactLayout != layout else { return }
        compactLayout = layout
        defaults.set(layout.rawValue, forKey: Key.compactLayout)
        changed?(.layout)
    }

    func setAccent(_ hex: String, provider: ProviderKind) {
        guard HUDAccentPalette.choices.contains(hex) else { return }
        if provider == .codex {
            guard codexAccentHex != hex else { return }
            codexAccentHex = hex
            defaults.set(hex, forKey: Key.codexAccentHex)
        } else {
            guard claudeAccentHex != hex else { return }
            claudeAccentHex = hex
            defaults.set(hex, forKey: Key.claudeAccentHex)
        }
        changed?(.appearance)
    }

    private func setAppearanceChoice(
        _ value: Double,
        choices: [Double],
        current: inout Double,
        key: String
    ) {
        guard choices.contains(value), current != value else { return }
        current = value
        defaults.set(value, forKey: key)
        changed?(.appearance)
    }

    private static func savedChoice(_ value: Double, choices: [Double], fallback: Double) -> Double {
        choices.contains(value) ? value : fallback
    }
}
